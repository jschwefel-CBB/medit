# GUI Test Driver — Design Spec

**Date:** 2026-06-16
**Status:** Draft for review
**Author:** Design session (Jason + Claude)

---

## 1. Problem

Manual GUI testing of native macOS apps is slow and repetitive. The current
loop for `medit` (and any other Mac app) is: make a change, launch the app,
hand-click through flows, eyeball the result. This does not scale, is not
reproducible, and provides no regression safety net at the UI level. The
existing `MeditKitTests` suite covers logic well but nothing drives the live
GUI.

We want a **reusable, app-agnostic tool** that drives and debugs *any* macOS
app through the Accessibility (AX) API, executing a **declarative test plan**
authored by an agent (or a human) and reporting structured results back. The
plan is the contract: whoever knows the app writes the plan; the tool knows
only how to drive a Mac GUI.

## 2. Goals

- Drive any macOS app via the Accessibility API: launch, click, type, key
  presses, scroll, wait, assert.
- Execute a **declarative, deterministic** test plan (JSON). Same plan + same
  app build → identical result, every run.
- Produce a **structured report** plus debugging artifacts (screenshots,
  AX-tree snapshots) on failure.
- Be invokable two ways over one shared engine: a **CLI** (CI/scripting) and an
  **MCP server** (live agent integration).
- Support **plan composition** (`include`) so shared setup is written once.
- Serve as the UI-level regression and debugging layer for `medit`, while
  remaining fully decoupled from it.

## 3. Non-Goals

- No LLM in the execution path. Plans are authored offline (by an agent or
  human); the executor runs them mechanically and deterministically.
- No cross-platform support. macOS only.
- Not a record/replay GUI recorder in v1 (plans are authored, not recorded).
- Not a load/performance tool.
- No driving of apps the operator is not authorized to test.

## 4. Key Design Decisions

These three decisions were made explicitly and shape everything below:

1. **Plan format: pure structured JSON. Deterministic always wins.**
   No natural-language steps, no LLM-resolved hints. A plan is a
   schema-validated list of steps. Reproducible and diffable.

2. **Element targeting: AX-first, deterministic vision fallback.**
   The Accessibility tree is the primary, deterministic locator. A vision
   fallback (template matching, fixed confidence threshold — *not* an LLM
   reasoning over a screenshot) covers custom-drawn UIs that do not expose
   accessibility. Vision returns coordinates only; it never makes semantic
   judgments.

3. **Executor form: both CLI and MCP, over one shared core.**
   A `GUIDriverCore` library does the real work. A thin CLI and a thin MCP
   server wrap it. Mirrors the existing `MeditKit` library + thin `App/`
   pattern.

## 5. Architecture

Three layers with the **plan as the only contract** between the agent and the
executor. The agent is *offline* — it authors plans and reads reports; it is
never in the execution hot path.

```
┌─────────────────────────────────────────────────────────────┐
│  Agent (authors plans, reads reports — OFFLINE, not in loop) │
└───────────────┬──────────────────────────┬──────────────────┘
                │ writes plan.json          │ reads report.json
                ▼                           ▲
┌──────────────────────────┐   ┌──────────────────────────────┐
│  CLI front-end           │   │  MCP server front-end        │
│  `guidriver run p.json`  │   │  tools: run_plan, get_report │
└───────────┬──────────────┘   └───────────────┬──────────────┘
            │                                   │
            └─────────────┬─────────────────────┘
                          ▼
        ┌───────────────────────────────────────┐
        │  GUIDriverCore  (the engine library)   │
        │  ┌─────────────────────────────────┐   │
        │  │ PlanParser    (JSON → Plan)     │   │
        │  │ Targeting     (selector → AXEl) │   │
        │  │   ├─ AXResolver  (primary)      │   │
        │  │   └─ VisionResolver (fallback)  │   │
        │  │ ActionEngine  (click/type/…)    │   │
        │  │ AssertionEngine (verify state)  │   │
        │  │ Reporter      (→ report.json)   │   │
        │  └─────────────────────────────────┘   │
        └───────────────────────────────────────┘
                          │ macOS Accessibility API (AX*)
                          ▼
              ┌────────────────────────┐
              │  Target app (any Mac   │
              │  app: medit, or other) │
              └────────────────────────┘
```

**Boundaries:**

- **Core is a library** (`GUIDriverCore`); front-ends are thin shells.
- The **plan is the only contract**. An agent never talks to the target app
  directly. The plan schema is versioned.
- The executor is **app-agnostic**: it knows AX roles, identifiers, and the
  plan schema — nothing about `medit`. `medit` is simply "test target #1."
- Driving another app requires macOS **Accessibility** (and likely
  **Automation**) permissions; the tool detects and reports missing
  permissions explicitly rather than failing opaquely.

## 6. The Plan Schema (agent ↔ executor contract)

A plan is a JSON document: metadata + an ordered list of steps. Each step is one
action or assertion. Everything is declarative and deterministic.

```jsonc
{
  "schemaVersion": "1.0",
  "name": "medit: open file and verify line count",
  "include": ["setups/launch-and-open.json"],   // optional composition
  "target": {
    "bundleId": "com.jschwefel.medit",           // or "path": "/Applications/Foo.app"
    "launchArgs": ["--reset-state"],             // optional
    "launchFiles": ["/tmp/sample.txt"]           // optional: open with these files
  },
  "defaults": { "timeoutMs": 5000, "retryIntervalMs": 100 },
  "steps": [
    {
      "id": "click-open",
      "action": "click",
      "target": { "role": "AXButton", "identifier": "openButton" }
    },
    {
      "id": "type-text",
      "action": "type",
      "target": { "role": "AXTextArea", "identifier": "editorTextView" },
      "args": { "text": "hello\nworld" }
    },
    {
      "id": "assert-status",
      "action": "assert",
      "target": { "role": "AXStaticText", "identifier": "lineCountLabel" },
      "assert": { "property": "value", "op": "equals", "expected": "2 lines" }
    }
  ]
}
```

### 6.1 Selector model

A selector is a set of AX predicates ANDed together. Resolution priority is
**fixed and documented**:

1. `identifier` (AXIdentifier) — gold standard, set in code. Unique → exact
   match.
2. `role` + `label` / `title` / `value` — when no identifier is available.
3. `path` — an ordered index path through the AX tree (e.g.
   `window[0]/group[2]/button[0]`) as a positional fallback.
4. `vision` — `{ "image": "open-icon.png", "confidence": 0.9 }` deterministic
   template match, last resort, returns center coordinates. No LLM.

**A selector that matches zero or more than one element is a hard error.**
Ambiguity is a bug in the plan; the run fails loudly with a diagnostic dump of
the nearby AX subtree rather than guessing.

### 6.2 Action vocabulary (v1 — lean)

`launch`, `terminate`, `click`, `doubleClick`, `rightClick`, `type`,
`keyPress` (e.g. `cmd+s`), `setValue`, `scroll`, `waitFor` (element appears /
disappears), `screenshot`, `assert`.

Deferred to later phases (explicitly out of v1): drag-and-drop, deep menu-bar
navigation, AppleScript escape hatch. Added only when real plans demand them.

### 6.3 Assertion operators

`equals`, `notEquals`, `contains`, `matches` (regex), `exists`, `notExists`,
`greaterThan`, `lessThan` (numeric).

Each asserts on an element `property` (`value`, `title`, `enabled`, `focused`,
`position`, `size`) or on app-level state (`exists` / `notExists` of an
element).

### 6.4 Composition (`include`)

A plan may carry a top-level `include: [...]` listing reusable sub-plan files,
resolved relative to the including plan. Included steps are **prepended** in
order before the host plan's own steps (shared setup like "launch + open a
file"). Resolution is static file inclusion — no dynamic logic, fully
deterministic. Includes are **cycle-detected** and **depth-limited**. A
sub-plan is a normal plan file; when included, its `target`/`defaults` may be
inherited or overridden by the host (host wins on conflict).

### 6.5 Determinism guarantees

- **No timing assumptions.** Every step polls until its precondition holds or
  the timeout fires (`waitFor` semantics everywhere). A slow machine does not
  change outcomes.
- `sleep(n)` is **not** a synchronization primitive. A bare `wait` action
  exists but is explicitly discouraged and flagged in review.
- Same plan + same app build → same result, always.

## 7. Targeting Engine (selector → element)

The `Targeting` component takes a selector and returns exactly one element
handle (or fails). Resolution pipeline is deterministic and ordered:

1. **AXResolver** walks the target app's AX tree
   (`AXUIElementCopyAttributeValue`, etc.), filtering by the selector's
   predicates in priority order (§6.1). Handles essentially all of a well-built
   app.
2. If AX yields nothing **and** the selector carries a `vision` block,
   **VisionResolver** runs deterministic template matching (normalized
   cross-correlation against a screenshot, fixed confidence threshold) and
   returns center coordinates. No LLM; no semantic guessing.
3. **0 or >1 match → hard error**, with a diagnostic dump of the nearby AX
   subtree so the plan can be fixed.

**Vision-derived coordinates are still actionable:** actions accept either an
element handle (AX) or a point (vision). Click-at-point and type-at-focused-point
work without an AX handle.

**Known limitation:** property assertions (reading `value`, `title`, etc.) are
**not** available for vision-only elements — you cannot read a property off a
pixel region. The cure is AX identifiers. The spec recommends AX identifiers
for anything you need to assert against; vision is reserved for clicking
custom-drawn controls that expose no accessibility.

## 8. Reporting (executor → agent)

The executor emits a structured `report.json` plus human-readable stdout.

```jsonc
{
  "plan": "medit: open file and verify line count",
  "result": "fail",
  "durationMs": 4210,
  "steps": [
    { "id": "click-open", "result": "pass", "durationMs": 120 },
    { "id": "type-text",  "result": "pass", "durationMs": 340 },
    { "id": "assert-status", "result": "fail",
      "expected": "2 lines", "actual": "1 line",
      "screenshot": "artifacts/assert-status.png",
      "axDump": "artifacts/assert-status.axtree.json" }
  ],
  "permissions": { "accessibility": true, "automation": true }
}
```

- **First failure stops the run by default** (`--keep-going` to continue), so
  the agent gets the earliest signal.
- **On failure, auto-capture a screenshot + AX-tree snapshot** as artifacts.
  This is what makes the tool a *debugging* aid, not just pass/fail: the agent
  reads `actual`, the screenshot, and the tree to self-correct the plan or the
  app.
- **CI exit codes:** `0` pass; non-zero fail/error; **permission problems get a
  distinct exit code** so they are never confused with test failures.
- The MCP `run_plan` tool returns this same JSON inline so an agent receives it
  in-loop.

## 9. Permissions & Security

- Driving another app's GUI requires the macOS **Accessibility** TCC permission
  (`AXIsProcessTrusted`); launching/controlling apps may also require
  **Automation**. The executor **preflight-checks** these and emits a distinct
  error + exit code with exact grant instructions, rather than silently
  failing.
- For unsigned local dev builds, macOS ties TCC grants to the specific binary;
  the docs explain granting the permission to the CLI binary and/or the
  terminal that runs it.
- The tool **only drives apps** via synthesized input events and reads the AX
  tree. No private API, no network egress in the core. Vision template images
  are local files.
- **Security posture:** this is a developer automation harness. Plans are
  trusted input (they can drive arbitrary UI). Run it only against apps you own
  or are authorized to test.

## 10. `medit` Integration (test target #1)

- **Add `AXIdentifier`s** to key controls: editor `NSTextView`, status-bar
  line/column labels, find/replace fields, sidebar outline, Go-to-line sheet,
  reload-banner buttons. Small, mechanical PR in `medit`; the single biggest
  reliability lever — it moves `medit` almost entirely onto the deterministic
  AX path and reserves vision for genuinely custom-drawn bits.
- **Deterministic preconditions:** a `--reset-state` launch path (or a
  test-only defaults domain) so plans start from a known state.
- **Starter plan suite** committed under `medit` (e.g. a `uitests/` dir): launch,
  open file, type, verify line count, find/replace, go-to-line, external-change
  reload banner.
- A short **"making an app testable" checklist** lives alongside the tool docs.

The tool itself remains a **separate package** — it is not coupled to `medit`.

## 11. Project Shape

A standalone SwiftPM package, mirroring the existing `MeditKit` library + thin
wrapper convention:

```
GUIDriver/
  Package.swift
  Sources/
    GUIDriverCore/      # engine library: parser, targeting, actions, assertions, reporter
    guidriver/          # CLI executable (thin)
    GUIDriverMCP/       # MCP server executable (thin)
  Tests/
    GUIDriverCoreTests/ # unit + integration tests
  Fixtures/
    TestHostApp/        # tiny AppKit app with known AX identifiers, to test the driver itself
```

## 12. Testing the Tester

A flaky test tool is worthless, so the tool is validated against ground truth:

- **TestHostApp fixture** — a tiny AppKit app with deterministic, known AX
  identifiers. The core's tests drive *it*, verifying the engine without
  depending on `medit`.
- **Unit tests** for: PlanParser (schema validation, `include` resolution,
  cycle detection, depth limit), selector resolution ordering, every assertion
  operator, report generation — all without a GUI.
- **Integration tests** that run real plans against TestHostApp end to end.

## 13. Build Phases (each independently shippable)

1. **Core engine** — plan schema + PlanParser + AXResolver + ActionEngine +
   AssertionEngine + Reporter, driven by TestHostApp. No vision, no MCP. This
   alone replaces most manual clicking.
2. **CLI front-end** — `guidriver run`, exit codes, failure artifacts,
   permission preflight.
3. **Composition + polish** — `include` resolution, `waitFor` hardening, richer
   assertions.
4. **MCP server front-end** — over the same core (`run_plan`, `get_report`).
5. **VisionResolver** — deterministic template-match fallback.
6. **`medit` integration** — add AXIdentifiers, commit starter plan suite,
   `--reset-state`.

This ordering ships value at phase 1 and defers the two hardest/most-optional
pieces (vision, MCP) to the end.

## 14. Open Questions / Future Work

- **Multi-window / sheet disambiguation** beyond `path` selectors — may need a
  richer window/sheet scoping predicate as suites grow.
- **Drag-and-drop and deep menu-bar navigation** — deferred from v1; revisit
  when a real plan needs them.
- **Record-assist** — a future helper that dumps the live AX tree of a running
  app to help authors discover identifiers/roles (authoring aid, not part of
  the deterministic executor).
- **Parallel runs** — running plans against multiple app instances
  concurrently; out of scope for v1.
