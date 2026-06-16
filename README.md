# Clicky → a B2B SaaS employee onboarding tool

**Heads up: this is a work in progress.** I'm modifying this project into a B2B SaaS onboarding tool for IT teams.

This repo started life as [Clicky](https://www.clicky.so/) — Farza's open-source (MIT) AI buddy that lives next to your cursor, sees your screen, talks to you, and points at stuff. Huge credit to him for the foundation. I'm building on top of it to turn it into something aimed at companies instead of individual learners.

## What I'm building

The pitch: when a new hire joins a company, their IT team shouldn't have to write a 40-page setup PDF or hop on a screen-share for every laptop. Instead, IT authors an ordered checklist of onboarding steps **once**, and every new employee gets an AI guide living in their macOS menu bar that walks them through it — showing text guidance and flying a cursor right to the buttons they need to click.

It reuses Clicky's core machinery (screenshot → Claude → on-screen pointing) and layers a guided, step-by-step onboarding product on top of it.

### How the onboarding flow works

1. **IT authors a flow.** A company's IT team builds an ordered list of setup steps in a web admin page (`GET /admin`), stored in Cloudflare KV. Each flow has a title and numbered steps.
2. **The app loads a flow.** The menu bar app fetches a flow by id (`GET /flow/:id`, defaulting to the `OnboardingFlowID` Info.plist key or `"demo"`) and renders it as a checklist in the panel.
3. **The new hire works through it.** For each step they can press **Tell me** (Clicky explains the step in text and points the blue overlay cursor at the right element) or **Show me** (Clicky actually performs the step — it glides the _real_ macOS cursor to the spot and clicks). Both capture the screen and send the current step + screenshot to Claude with a step-aware prompt.
4. **They advance.** **Done** moves to the next step; **Start again** resets to step one.

This flow reuses the existing screenshot → Claude → `[POINT:...]` pipeline, so it needs no voice (speech-to-text / text-to-speech) APIs to function — though the original voice companion still works if you wire those up.

> ⚠️ **Show me** auto-clicks based on Claude's pixel guess of where the element is. Accuracy is unvalidated — a wrong coordinate clicks the wrong thing. Treat it as experimental.

---

### Original Clicky context (the foundation this is built on)

Clicky is an AI teacher that lives as a buddy next to your cursor. It can see your screen, talk to you, and even point at stuff — kinda like having a real teacher next to you. Here's the [original tweet](https://x.com/FarzaTV/status/2041314633978659092) that blew up for a demo, and the original project is MIT licensed, so you can hack on it, fork it, or build a company out of it.

![Clicky — an ai buddy that lives on your mac](clicky-demo.gif)

## Get started with Claude Code

The fastest way to get this running is with [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Once you get Claude running, paste this:

```
Hi Claude.

This is a macOS menu bar app I'm turning into a B2B SaaS employee
onboarding tool, built on top of the open-source Clicky project.

Read the AGENTS.md (CLAUDE.md is a symlink to it). I want to get it
running locally on my Mac.

Help me set up everything — the Cloudflare Worker with my own API keys
and KV namespace, the proxy URLs, the onboarding admin page, and getting
it building in Xcode. Walk me through it.
```

That's it. It'll read the docs and walk you through the whole setup. Once you're running you can just keep talking to it — build features, fix bugs, whatever.

## Manual setup

If you want to do it yourself, here's the deal.

### Prerequisites

- macOS 14.2+ (for ScreenCaptureKit)
- Xcode 15+
- Node.js 18+ (for the Cloudflare Worker)
- A [Cloudflare](https://cloudflare.com) account (free tier works)
- An [Anthropic](https://console.anthropic.com) API key (required — powers the onboarding guidance and pointing)
- Optional: [AssemblyAI](https://www.assemblyai.com) + [ElevenLabs](https://elevenlabs.io) keys — only needed for the original voice companion. The onboarding flow works without them.

### 1. Set up the Cloudflare Worker

The Worker is a tiny proxy that holds your API keys. The app talks to the Worker, the Worker talks to the APIs. This way your keys never ship in the app binary.

```bash
cd worker
npm install
```

Now add your secrets. Wrangler will prompt you to paste each one. Only `ANTHROPIC_API_KEY` is required for the onboarding flow — the other two are for the optional voice companion:

```bash
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY   # optional (voice input)
npx wrangler secret put ELEVENLABS_API_KEY   # optional (voice output)
```

For the ElevenLabs voice ID, open `wrangler.toml` and set it there (it's not sensitive):

```toml
[vars]
ELEVENLABS_VOICE_ID = "your-voice-id-here"
```

The onboarding flows are stored in a Cloudflare KV namespace. Create one and bind it as `ONBOARDING_FLOWS`:

```bash
npx wrangler kv namespace create ONBOARDING_FLOWS
```

Wrangler prints an `id` — add the binding to `wrangler.toml`:

```toml
[[kv_namespaces]]
binding = "ONBOARDING_FLOWS"
id = "your-namespace-id-here"
```

Deploy it:

```bash
npx wrangler deploy
```

It'll give you a URL like `https://your-worker-name.your-subdomain.workers.dev`. Copy that.

Once deployed, IT teams author onboarding flows at `https://your-worker-url/admin`. The app then loads a flow by id via `GET /flow/:id`.

> ⚠️ In the MVP, the `/admin` page and `PUT /flow/:id` are **unauthenticated**. Put them behind auth before any real deployment.

### 2. Run the Worker locally (for development)

If you want to test changes to the Worker without deploying:

```bash
cd worker
npx wrangler dev
```

This starts a local server (usually `http://localhost:8787`) that behaves exactly like the deployed Worker, including a simulated `ONBOARDING_FLOWS` KV namespace and the `/admin` authoring page. You'll need to create a `.dev.vars` file in the `worker/` directory with your keys:

```
ANTHROPIC_API_KEY=sk-ant-...
ASSEMBLYAI_API_KEY=...
ELEVENLABS_API_KEY=...
ELEVENLABS_VOICE_ID=...
```

Then update the proxy URLs in the Swift code to point to `http://localhost:8787` instead of the deployed Worker URL while developing. Grep for `clicky-proxy` to find them all.

### 3. Update the proxy URLs in the app

The app has the Worker URL hardcoded in a few places. Search for `your-worker-name.your-subdomain.workers.dev` and replace it with your Worker URL:

```bash
grep -r "clicky-proxy" leanring-buddy/
```

You'll find it in:

- `CompanionManager.swift` — Claude chat + ElevenLabs TTS
- `OnboardingFlow.swift` — `GET /flow/:id` flow fetching
- `AssemblyAIStreamingTranscriptionProvider.swift` — AssemblyAI token endpoint

### 4. Point the app at an onboarding flow

The app loads a flow by id on launch. Set the `OnboardingFlowID` key in `leanring-buddy/Info.plist` to the id of a flow you authored at `/admin`. If it's missing, the app falls back to the `"demo"` flow.

### 5. Open in Xcode and run

```bash
open leanring-buddy.xcodeproj
```

In Xcode:

1. Select the `leanring-buddy` scheme (yes, the typo is intentional, long story)
2. Set your signing team under Signing & Capabilities
3. Hit **Cmd + R** to build and run

The app will appear in your menu bar (not the dock). Click the icon to open the panel, grant the permissions it asks for, and you're good.

### Permissions the app needs

- **Screen Recording** — for taking screenshots of the step the new hire is on
- **Screen Content** — for ScreenCaptureKit access
- **Accessibility** — for moving the cursor overlay and the global keyboard shortcut
- **Microphone** — only for the optional push-to-talk voice companion

## Architecture

If you want the full technical breakdown, read `AGENTS.md` (`CLAUDE.md` is a symlink to it). But here's the short version:

**Menu bar app** (no dock icon) with two `NSPanel` windows — one for the control panel dropdown, one for the full-screen transparent cursor overlay.

For **onboarding**, the panel shows a checklist loaded from the Worker (`GET /flow/:id`). For each step the new hire can tap **Tell me** (Claude explains it in text and the blue overlay cursor points at the element) or **Show me** (Clicky drives the _real_ macOS cursor to Claude's coordinate and clicks, performing the step via synthetic `CGEvent`s). Both send a screenshot + the current step to Claude with a step-aware prompt. IT teams author these flows at `/admin`, stored in Cloudflare KV.

For the optional **voice companion** (inherited from Clicky), push-to-talk streams audio over a websocket to AssemblyAI, sends the transcript + screenshot to Claude via streaming SSE, and plays the response through ElevenLabs TTS.

In both modes, Claude can embed `[POINT:x,y:label:screenN]` tags in its responses to make the cursor fly to specific UI elements across multiple monitors. All APIs are proxied through a Cloudflare Worker so no keys ship in the app.

## Project structure

```
leanring-buddy/            # Swift source (yes, the typo stays)
  CompanionManager.swift      # Central state machine + onboarding flow logic
  OnboardingFlow.swift        # Flow models + GET /flow/:id client
  OnboardingPanelView.swift   # Onboarding checklist UI
  CompanionPanelView.swift    # Menu bar panel UI
  ClaudeAPI.swift             # Claude streaming client
  OverlayWindow.swift         # Blue cursor overlay + pointing
  ElevenLabsTTSClient.swift   # Text-to-speech playback (optional voice)
  AssemblyAI*.swift           # Real-time transcription (optional voice)
  BuddyDictation*.swift       # Push-to-talk pipeline (optional voice)
worker/                    # Cloudflare Worker proxy
  src/index.ts                # Routes: /chat, /tts, /transcribe-token,
                              #         GET/PUT /flow/:id, GET /admin
  src/adminPage.ts            # IT-facing flow authoring page
AGENTS.md                  # Full architecture doc (agents read this; CLAUDE.md symlinks here)
```

## Status & contributing

This is an active work in progress as I reshape Clicky into a B2B onboarding tool. Expect rough edges. If you're using Claude Code, it already knows the codebase — just tell it what you want to build and point it at `AGENTS.md`.

Built on the open-source [Clicky](https://www.clicky.so/) by [@farzatv](https://x.com/farzatv) — MIT licensed.
