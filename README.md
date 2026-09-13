# Wow-Addon

Addon source for **DummyAnalyzer**, a World of Warcraft (Midnight 12.x, Interface 120005) training-dummy DPS analyzer and GRIP-EMS sequence optimizer.

## What it does

- **Track tests** — auto-starts on combat, captures casts, buff uptimes, damage, resource data
- **Generate reports** — per-spell breakdowns, DPS, cast frequency, buff uptime, opener analysis
- **Import SimC** — parses SimulationCraft paste output (48 spell / 13 buff mappings), maps names, filters procs/passives
- **Compare logs** — side-by-side comparison, positional analysis, SimC gap analysis
- **Optimize sequences** — IterateSequence feedback loop + hill-climber optimizer (3000-iter cap, plateau detection), interleave selection scored on the real GRIP-EMS add-cast expansion
- **Export** — plain-text GRIP-EMS format and `!EMS1!` CBOR-compressed import strings

## Install

1. Copy `DummyAnalyzer/` into `Interface/AddOns/` (retail), keeping the `Skins/` subfolder intact.
2. Load the game; the addon creates a minimap button and slash commands `/_dummy_`-style aliases `/dummy` and `/dummydebug` (`/dummydebug level 0-3`): `0` off, `1` warn, `2` info, `3` verbose.
3. Paste a SimC report (optional) and run a dummy test to capture baseline data.

## Dependencies

**GRIP-EMS** (v3+ plugin API, `GRIPEMS.API`) is required for:
- Detecting active sequences and importing existing steps
- Registering DummyAnalyzer as a reversible plugin (`RegisterPlugin` with `OnEnable`/`OnDisable` callbacks passed by reference)
- Pushing optimized sequences (`UpdateSequence` / `CreateSequence`)
- Generating `!EMS1!` CBOR import strings

Without GRIP-EMS loaded, DummyAnalyzer degrades gracefully: testing, reports, SimC import, and sequence editing all still work; EMS push/import are disabled with a chat notice.

## Repo layout

- `DummyAnalyzer/` — the addon (single-toc multi-file module layout)
- `DummyAnalyzer/tests/` — standalone regression harnesses (`luajit file.lua`; no WoW client needed)
- Load-order modules: `Init.lua` (state/debug), `DamageTracking.lua`, `BuffTracking.lua`, `SimCImport.lua`, `SequenceBuilder.lua`, `SequenceCore.lua`, `SequenceOptimizer.lua`, `PluginHandshake.lua`, `MainUI.lua`, `SavedLogsDb.lua`, `SavedLogsBrowser.lua`, `SavedLogsLogic.lua`, `ReportGen.lua`, etc.

## Known constraints (WoW 12.x)

No Ace3/external libs — pure WoW API. Combat data via `C_DamageMeter`, never `COMBAT_LOG_EVENT_UNFILTERED`. Aura names are secret strings — never compared directly; `pcall`-safe resolution only. `GetSpellInfo` returns spellId second; use `C_Spell.GetSpellName`.

## Development

Developer-only scaffolding (`REFACTOR_SPEC.md`, `WORKFLOW_GUIDE.md`, `auto-sync.ps1`) lives under `.dev/` and is gitignored so personal machine paths never enter the public tree. `auto-sync.ps1` mirrors sources into the local WoW addon directory and verifies SHA-256.

Run the regression suites after touching sequence logic:

```
cd DummyAnalyzer/tests
luajit sel_interleave_test.lua
luajit interleave_add_test.lua
luajit ems_weave_test.lua
luajit interleave_pipeline_test.lua
luajit fitness_snapshot_test.lua
```