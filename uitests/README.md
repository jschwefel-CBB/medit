# medit GUI tests (autopilot)

These are declarative GUI test plans executed by `autopilot`
(`~/repositories/autopilot`). They drive the built medit app via the
macOS Accessibility API.

## Prerequisites
- Build autopilot: `(cd ~/repositories/autopilot && swift build)`
- Grant Accessibility permission to the terminal/binary running autopilot
  (`autopilot doctor` checks this).
- medit must be installed (so `bundleId` resolves) or its built `.app` path
  supplied via the plan `target.path`.

## Run a plan
```bash
~/repositories/autopilot/.build/debug/autopilot run \
  ~/repositories/medit/uitests/open-and-type.json \
  --artifacts /tmp/medit-uitests
```
Exit codes: 0 pass, 1 test failure, 2 plan error, 3 permission missing.

## Authoring
For the complete plan format — actions, assertions, selectors, hygiene
patterns, and a worked example — see the autopilot authoring guide:
`~/repositories/autopilot/docs/AUTHORING.md`
(or https://github.com/jschwefel-CBB/autopilot/blob/main/docs/AUTHORING.md).

Use the MCP `dump_axtree` tool (or read these plans) to discover identifiers.

Tagged controls (AXIdentifier):
- `editorTextView` — the editing surface (NSTextView)
- `positionLabel` — status-bar line/column text
- `languageButton`, `encodingButton` — status-bar inline buttons
- `findField`, `replaceField`, `findStatusLabel` — find/replace bar
- `sidebarOutline` — file-browser outline view
- `goToLineField` — go-to-line sheet input
- `reloadButton`, `dismissReloadButton`, `reloadBannerLabel` — external-change banner

## Note on state
Plans launch medit with `--reset-state`, which clears its UserDefaults domain
at startup so each run begins from a known baseline.
