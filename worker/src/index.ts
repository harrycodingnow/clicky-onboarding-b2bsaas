/**
 * Clicky Proxy + Onboarding Worker
 *
 * Two responsibilities:
 *   1. Proxies requests to Claude / ElevenLabs / AssemblyAI so the app never
 *      ships with raw API keys. Keys are stored as Cloudflare secrets.
 *   2. Stores onboarding flows (the ordered steps a new employee follows) in
 *      KV, and serves a small admin page for IT to author them.
 *
 * Routes:
 *   POST /chat              → Anthropic Messages API (streaming)
 *   POST /tts               → ElevenLabs TTS API
 *   POST /transcribe-token  → AssemblyAI short-lived streaming token
 *   GET  /flow/:id          → Fetch an onboarding flow as JSON
 *   PUT  /flow/:id          → Create or replace an onboarding flow
 *   GET  /admin             → Flow authoring page for IT
 */

import { adminPageHTML } from "./adminPage";

/// Minimal shape of the KV namespace we use, so the Worker stays free of the
/// optional @cloudflare/workers-types dependency.
interface OnboardingFlowsKV {
  get(key: string): Promise<string | null>;
  put(key: string, value: string): Promise<void>;
}

interface Env {
  ANTHROPIC_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
  ASSEMBLYAI_API_KEY: string;
  ONBOARDING_FLOWS: OnboardingFlowsKV;
}

interface OnboardingStep {
  id: number;
  instruction: string;
}

interface OnboardingFlow {
  id: string;
  title: string;
  steps: OnboardingStep[];
  updatedAt: string;
}

// Guard rails so a malformed or abusive PUT can't store unbounded data.
const MAX_TITLE_LENGTH = 200;
const MAX_STEPS = 50;
const MAX_INSTRUCTION_LENGTH = 500;
const MAX_FLOW_ID_LENGTH = 64;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const method = request.method;

    try {
      // Onboarding admin page
      if (method === "GET" && url.pathname === "/admin") {
        return new Response(adminPageHTML, {
          status: 200,
          headers: { "content-type": "text/html; charset=utf-8" },
        });
      }

      // Onboarding flow storage: /flow/:id
      if (url.pathname.startsWith("/flow/")) {
        const flowId = decodeURIComponent(url.pathname.slice("/flow/".length));
        if (method === "GET") return await handleGetFlow(flowId, env);
        if (method === "PUT") return await handlePutFlow(flowId, request, env);
        return new Response("Method not allowed", { status: 405 });
      }

      // API proxy routes (POST only)
      if (method === "POST") {
        if (url.pathname === "/chat") return await handleChat(request, env);
        if (url.pathname === "/tts") return await handleTTS(request, env);
        if (url.pathname === "/transcribe-token") return await handleTranscribeToken(env);
      }
    } catch (error) {
      console.error(`[${url.pathname}] Unhandled error:`, error);
      return new Response(
        JSON.stringify({ error: String(error) }),
        { status: 500, headers: { "content-type": "application/json" } }
      );
    }

    return new Response("Not found", { status: 404 });
  },
};

// MARK: - Onboarding flow storage

function isValidFlowId(flowId: string): boolean {
  // Keep IDs URL- and key-safe: letters, numbers, dash, underscore.
  return /^[a-zA-Z0-9_-]+$/.test(flowId) && flowId.length <= MAX_FLOW_ID_LENGTH;
}

async function handleGetFlow(flowId: string, env: Env): Promise<Response> {
  if (!isValidFlowId(flowId)) {
    return new Response(JSON.stringify({ error: "Invalid flow id." }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const storedFlow = await env.ONBOARDING_FLOWS.get(`flow:${flowId}`);
  if (storedFlow === null) {
    return new Response(JSON.stringify({ error: "Flow not found." }), {
      status: 404,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(storedFlow, {
    status: 200,
    headers: { "content-type": "application/json", "cache-control": "no-cache" },
  });
}

async function handlePutFlow(flowId: string, request: Request, env: Env): Promise<Response> {
  if (!isValidFlowId(flowId)) {
    return new Response(JSON.stringify({ error: "Invalid flow id." }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  let parsedBody: unknown;
  try {
    parsedBody = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: "Body must be valid JSON." }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const validationResult = validateFlowInput(parsedBody);
  if (!validationResult.ok) {
    return new Response(JSON.stringify({ error: validationResult.error }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const flow: OnboardingFlow = {
    id: flowId,
    title: validationResult.title,
    steps: validationResult.steps,
    updatedAt: new Date().toISOString(),
  };

  await env.ONBOARDING_FLOWS.put(`flow:${flowId}`, JSON.stringify(flow));

  return new Response(JSON.stringify(flow), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

type FlowValidationResult =
  | { ok: true; title: string; steps: OnboardingStep[] }
  | { ok: false; error: string };

function validateFlowInput(input: unknown): FlowValidationResult {
  if (typeof input !== "object" || input === null) {
    return { ok: false, error: "Body must be a JSON object." };
  }

  const candidate = input as { title?: unknown; steps?: unknown };

  if (typeof candidate.title !== "string" || candidate.title.trim().length === 0) {
    return { ok: false, error: "title is required." };
  }
  if (candidate.title.length > MAX_TITLE_LENGTH) {
    return { ok: false, error: `title must be ${MAX_TITLE_LENGTH} characters or fewer.` };
  }

  if (!Array.isArray(candidate.steps) || candidate.steps.length === 0) {
    return { ok: false, error: "steps must be a non-empty array." };
  }
  if (candidate.steps.length > MAX_STEPS) {
    return { ok: false, error: `A flow can have at most ${MAX_STEPS} steps.` };
  }

  const normalizedSteps: OnboardingStep[] = [];
  for (let index = 0; index < candidate.steps.length; index++) {
    const rawStep = candidate.steps[index] as { instruction?: unknown };
    if (typeof rawStep.instruction !== "string" || rawStep.instruction.trim().length === 0) {
      return { ok: false, error: `Step ${index + 1} is missing an instruction.` };
    }
    if (rawStep.instruction.length > MAX_INSTRUCTION_LENGTH) {
      return { ok: false, error: `Step ${index + 1} is too long (max ${MAX_INSTRUCTION_LENGTH}).` };
    }
    // Re-number server-side so step ids are always clean and sequential.
    normalizedSteps.push({ id: index + 1, instruction: rawStep.instruction.trim() });
  }

  return { ok: true, title: candidate.title.trim(), steps: normalizedSteps };
}

// MARK: - API proxy routes

async function handleChat(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/chat] Anthropic API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

async function handleTranscribeToken(env: Env): Promise<Response> {
  const response = await fetch(
    "https://streaming.assemblyai.com/v3/token?expires_in_seconds=480",
    {
      method: "GET",
      headers: {
        authorization: env.ASSEMBLYAI_API_KEY,
      },
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/transcribe-token] AssemblyAI token error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleTTS(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  const voiceId = env.ELEVENLABS_VOICE_ID;

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body,
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tts] ElevenLabs API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}
