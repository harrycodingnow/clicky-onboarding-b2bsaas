/**
 * Admin authoring page for onboarding flows.
 *
 * Served by the Worker at GET /admin. A company's IT team uses this single
 * page to type the ordered steps a new employee should follow. The page reads
 * and writes flows through the Worker's /flow/:id routes (same origin, so no
 * CORS is involved).
 *
 * Note: this MVP page is intentionally unauthenticated. Before any real
 * deployment, put the /admin page and the PUT /flow/:id route behind auth.
 */
export const adminPageHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Clicky Onboarding — Flow Builder</title>
  <style>
    :root {
      --bg: #0f1115;
      --panel: #181b22;
      --panel-2: #20242e;
      --border: #2a2f3a;
      --text: #e7eaf0;
      --muted: #9aa3b2;
      --accent: #4c8dff;
      --accent-2: #2f6fe0;
      --danger: #ff5d5d;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.45;
    }
    .wrap { max-width: 760px; margin: 0 auto; padding: 32px 20px 80px; }
    h1 { font-size: 22px; margin: 0 0 4px; }
    .sub { color: var(--muted); font-size: 14px; margin: 0 0 24px; }
    .row { display: flex; gap: 10px; align-items: center; }
    .card {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 16px;
      margin-bottom: 16px;
    }
    label { display: block; font-size: 12px; color: var(--muted); margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.04em; }
    input[type="text"], textarea {
      width: 100%;
      background: var(--panel-2);
      border: 1px solid var(--border);
      border-radius: 8px;
      color: var(--text);
      padding: 10px 12px;
      font-size: 14px;
      font-family: inherit;
      resize: vertical;
    }
    input[type="text"]:focus, textarea:focus { outline: none; border-color: var(--accent); }
    button {
      cursor: pointer;
      border: 1px solid var(--border);
      background: var(--panel-2);
      color: var(--text);
      border-radius: 8px;
      padding: 9px 14px;
      font-size: 14px;
      font-family: inherit;
    }
    button:hover { border-color: var(--accent); }
    button.primary { background: var(--accent); border-color: var(--accent); color: #fff; font-weight: 600; }
    button.primary:hover { background: var(--accent-2); }
    button.icon { padding: 6px 10px; line-height: 1; }
    button.danger:hover { border-color: var(--danger); color: var(--danger); }
    .steps { display: flex; flex-direction: column; gap: 10px; }
    .step {
      display: flex;
      gap: 10px;
      align-items: flex-start;
      background: var(--panel-2);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 10px;
    }
    .step .num {
      flex: 0 0 26px;
      height: 26px;
      border-radius: 50%;
      background: var(--accent);
      color: #fff;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 13px;
      font-weight: 600;
      margin-top: 2px;
    }
    .step .body { flex: 1; }
    .step .controls { display: flex; flex-direction: column; gap: 6px; }
    .toolbar { display: flex; gap: 10px; margin-top: 16px; }
    .status { font-size: 13px; margin-left: auto; align-self: center; }
    .status.ok { color: #51d88a; }
    .status.err { color: var(--danger); }
    .grow { flex: 1; }
    .hint { color: var(--muted); font-size: 12px; margin-top: 6px; }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>Clicky Onboarding — Flow Builder</h1>
    <p class="sub">Type the steps a new employee should follow. Each step is one clear instruction. Clicky reads these on the employee's Mac and points at the right thing on their screen.</p>

    <div class="card">
      <label for="flowId">Flow ID</label>
      <div class="row">
        <input type="text" id="flowId" class="grow" value="demo" placeholder="e.g. acme-engineering" />
        <button id="loadBtn">Load</button>
      </div>
      <p class="hint">A short identifier for this onboarding flow. The Mac app fetches a flow by this ID.</p>
    </div>

    <div class="card">
      <label for="title">Flow title</label>
      <input type="text" id="title" placeholder="e.g. New Engineer Setup" />
    </div>

    <div class="card">
      <label>Steps</label>
      <div class="steps" id="steps"></div>
      <div class="toolbar">
        <button id="addStepBtn">+ Add step</button>
        <button id="saveBtn" class="primary">Save flow</button>
        <span class="status" id="status"></span>
      </div>
    </div>
  </div>

  <script>
    const stepsContainer = document.getElementById("steps");
    const statusEl = document.getElementById("status");

    function setStatus(message, kind) {
      statusEl.textContent = message;
      statusEl.className = "status" + (kind ? " " + kind : "");
    }

    function renumber() {
      [...stepsContainer.querySelectorAll(".step .num")].forEach((numEl, index) => {
        numEl.textContent = String(index + 1);
      });
    }

    // Build a step row using DOM APIs (never innerHTML) so any instruction
    // text the user types can't inject markup into the page.
    function makeStepRow(instructionText) {
      const stepRow = document.createElement("div");
      stepRow.className = "step";

      const numberBadge = document.createElement("div");
      numberBadge.className = "num";

      const bodyWrap = document.createElement("div");
      bodyWrap.className = "body";
      const instructionInput = document.createElement("textarea");
      instructionInput.rows = 2;
      instructionInput.placeholder = "e.g. Open Slack and join the #general channel";
      instructionInput.value = instructionText || "";
      bodyWrap.appendChild(instructionInput);

      const controls = document.createElement("div");
      controls.className = "controls";

      const upButton = document.createElement("button");
      upButton.className = "icon";
      upButton.title = "Move up";
      upButton.textContent = "↑";
      upButton.addEventListener("click", () => {
        const previous = stepRow.previousElementSibling;
        if (previous) stepsContainer.insertBefore(stepRow, previous);
        renumber();
      });

      const downButton = document.createElement("button");
      downButton.className = "icon";
      downButton.title = "Move down";
      downButton.textContent = "↓";
      downButton.addEventListener("click", () => {
        const next = stepRow.nextElementSibling;
        if (next) stepsContainer.insertBefore(next, stepRow);
        renumber();
      });

      const removeButton = document.createElement("button");
      removeButton.className = "icon danger";
      removeButton.title = "Remove step";
      removeButton.textContent = "✕";
      removeButton.addEventListener("click", () => {
        stepRow.remove();
        renumber();
      });

      controls.appendChild(upButton);
      controls.appendChild(downButton);
      controls.appendChild(removeButton);

      stepRow.appendChild(numberBadge);
      stepRow.appendChild(bodyWrap);
      stepRow.appendChild(controls);
      return stepRow;
    }

    function addStep(instructionText) {
      stepsContainer.appendChild(makeStepRow(instructionText));
      renumber();
    }

    function collectSteps() {
      return [...stepsContainer.querySelectorAll(".step textarea")]
        .map((textarea) => textarea.value.trim())
        .filter((instruction) => instruction.length > 0)
        .map((instruction, index) => ({ id: index + 1, instruction }));
    }

    async function loadFlow() {
      const flowId = document.getElementById("flowId").value.trim();
      if (!flowId) { setStatus("Enter a flow ID first.", "err"); return; }
      setStatus("Loading…");
      try {
        const response = await fetch("/flow/" + encodeURIComponent(flowId));
        if (response.status === 404) {
          // New flow — start from a small template so the page isn't empty.
          document.getElementById("title").value = "";
          stepsContainer.innerHTML = "";
          addStep("");
          setStatus("New flow — add steps and save.", "ok");
          return;
        }
        if (!response.ok) throw new Error("HTTP " + response.status);
        const flow = await response.json();
        document.getElementById("title").value = flow.title || "";
        stepsContainer.innerHTML = "";
        (flow.steps || []).forEach((step) => addStep(step.instruction));
        if (!stepsContainer.children.length) addStep("");
        setStatus("Loaded.", "ok");
      } catch (error) {
        setStatus("Failed to load: " + error.message, "err");
      }
    }

    async function saveFlow() {
      const flowId = document.getElementById("flowId").value.trim();
      const title = document.getElementById("title").value.trim();
      const steps = collectSteps();
      if (!flowId) { setStatus("Enter a flow ID first.", "err"); return; }
      if (!title) { setStatus("Add a flow title.", "err"); return; }
      if (!steps.length) { setStatus("Add at least one step.", "err"); return; }

      setStatus("Saving…");
      try {
        const response = await fetch("/flow/" + encodeURIComponent(flowId), {
          method: "PUT",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ title, steps }),
        });
        if (!response.ok) {
          const errorText = await response.text();
          throw new Error(errorText || ("HTTP " + response.status));
        }
        setStatus("Saved ✓", "ok");
      } catch (error) {
        setStatus("Failed to save: " + error.message, "err");
      }
    }

    document.getElementById("loadBtn").addEventListener("click", loadFlow);
    document.getElementById("addStepBtn").addEventListener("click", () => addStep(""));
    document.getElementById("saveBtn").addEventListener("click", saveFlow);

    // Load whatever is at the default flow ID on first open.
    loadFlow();
  </script>
</body>
</html>`;
