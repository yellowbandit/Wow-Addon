# DummyAnalyzer core.lua → module split SPEC

Target: split the single-file addon `H:\OPEN CODE WOW CHAT\Wow-Addon\DummyAnalyzer\core.lua` (8676 lines)
into 15 Lua module files + rewritten `DummyAnalyzer.toc`. Pure WoW API, NO Ace3. Lua 5.1 dialect (behavior must be byte-for-byte equivalent logic).

Source file to consume (read-only, do not modify): `H:\OPEN CODE WOW CHAT\Wow-Addon\DummyAnalyzer\core.lua`
Output dir: `H:\OPEN CODE WOW CHAT\Wow-Addon\DummyAnalyzer\` (same folder). REMOVE the old `core.lua` at the end of the task.

## Chunk mechanism
Every .toc-listed file receives the SAME addon table as its 2nd vararg. Each new file therefore MUST begin with:
```lua
local AddonName, Addon = ...
```
DO NOT rename `Addon`; this table is the shared namespace across all files.

## Section map (line: starting line in core.lua : section title) — boundaries are `-- ============================================` banners
1. 2    : PATHS & CONSTANTS
2. 71   : HELPER FUNCTIONS
3. 145  : DIALOG TEMPLATE
4. 212  : CORE VARIABLES
5. 529  : SAVED LOGS DATABASE
6. 556  : ULTRA SAFE SPELL NAME HELPER
7. 613  : DAMAGE TRACKING (C_DamageMeter)  [includes 868 Meter diagnostics, 945 in-combat capture]
8. 1121 : BUFF UPTIME TRACKING
9. 1410 : FORMAT HELPERS
10. 1460: SAVED LOGS: Save / Delete / Compare
11. 1879: SimC IMPORT
12. 2496: MARKDOWN / AI EXPORT
13. 3002: REPORT GENERATION
14. 3298: REPORT WINDOW + COPY DIALOG
15. 3492: SAVED LOGS BROWSER UI
16. 4057: TEST CONTROL
17. 4220: EMS SEQUENCE EXPORT
18. 4354: TALENT SCANNER
19. 4605: SUGGESTED SEQUENCE GENERATION  [sub-headers 4625..5274]
20. 5324: REASONING TEXT GENERATION
21. 5403: GAP REPORT
22. 5523: EMS IMPORT STRING GENERATION
23. 5674: ITERATIVE FEEDBACK
24. 6927: MAIN WINDOW, MINIMAP, SLASH, INIT
25. 7353: EMS EXPORT STANDALONE WINDOW
26. 7864: COMBAT LOG IMPORT
27. 8131: COMBAT-SAFE EVENT REGISTRATION
28. 8168: INITIALISATION
29. 8263: GRIP-EMS PLUGIN HANDSHAKE (Tier 0..5)

## Output files + source ranges (.toc load order — LISTED IN THIS ORDER in DummyAnalyzer.toc)
| # | File (in addon dir) | Source lines | Content |
|---|---------------------|--------------|---------|
| 1 | `Init.lua` | 1-528 | PATHS & CONSTANTS, HELPER FUNCTIONS (incl DebugLog, SafeSetFont, trackDialog/AllDialogs, C color table, CreateStyledFrame, CreateStyledButton + any other button/helper factories), DIALOG TEMPLATE (CreateDialog), CORE VARIABLES + ParseSequenceLines + BuildKidFriendlyDisplay |
| 2 | `SavedLogsDb.lua` | 529-612 | SAVED LOGS DATABASE + ULTRA SAFE SPELL NAME HELPER |
| 3 | `FormatHelpers.lua` | 1410-1459 | FORMAT HELPERS (incl Addon.ShortNum, Addon.FormatNumber glue) |
| 4 | `DamageTracking.lua` | 613-1120 | DAMAGE TRACKING incl BuildMeterDiag + in-combat capture |
| 5 | `BuffTracking.lua` | 1121-1409 | BUFF UPTIME TRACKING |
| 6 | `SavedLogsLogic.lua` | 1460-1878 | SAVED LOGS: Save/Delete/Compare/rename/notes |
| 7 | `SimCImport.lua` | 1879-2495 | SimC IMPORT |
| 8 | `ReportGen.lua` | 2496-3297 | MARKDOWN/AI EXPORT + REPORT GENERATION |
| 9 | `ReportWindow.lua` | 3298-3491 | REPORT WINDOW + COPY DIALOG |
| 10| `SavedLogsBrowser.lua` | 3492-4056 | SAVED LOGS BROWSER UI |
| 11| `TestControl.lua` | 4057-4219 | TEST CONTROL |
| 12| `SequenceCore.lua` | 4220-4604 | EMS SEQUENCE EXPORT + TALENT SCANNER |
| 13| `SequenceOptimizer.lua` | 4605-5522 | SUGGESTED SEQUENCE GENERATION + REASONING TEXT + GAP REPORT |
| 14| `SequenceFeed.lua` | 5523-6926 | EMS IMPORT STRING GENERATION + ITERATIVE FEEDBACK |
| 15| `MainUI.lua` | 6927-8262 | MAIN WINDOW/MINIMAP/SLASH/INIT + EMS EXPORT STANDALONE WINDOW + COMBAT LOG IMPORT + COMBAT-SAFE EVENT REGISTRATION + INITIALISATION |
| 16| `PluginHandshake.lua` | 8263-8675 | GRIP-EMS PLUGIN HANDSHAKE (Tier 0..5) |

NOTE: FormatHelpers (file 3) must be loaded BEFORE any file that uses `ShortNum`/`Addon.ShortNum` at load time; with alias pattern below it is safe anywhere after Init. Keep the numbering above as the .toc order (FormatHelpers is listed right after SavedLogsDb only for clarity; alias pattern makes order non-critical after Init).

## Namespace promotion rules (THE critical part)
Goal: EXACT behavior parity. All constants/state/functions that are referenced from MORE THAN ONE module must live on `Addon.*`.

### A) State / constants / helpers defined in Init.lua
- Mutable shared state (testActive, startTime, testEndTime, spellHistory, currentDuration, updateFrame, timerFrame, currentWindow, damageData, totalDamage, damage counters, buff/debuff tables, meter session vars, etc. — EVERY file-scope `local` declared in the CORE VARIABLES section that any other module touches) MUST become `Addon.<name>`.
- In Init.lua, REPLACE the declaration `local testActive = false` with `Addon.testActive = false`, and every use inside Init.lua with `Addon.testActive`. Do the same for every promoted variable. Update every reference in every OTHER file to `Addon.<name>`.
- Constants that are immutable AND widely referenced (FONT paths, MAIN_FONT, BOLD_FONT, C color table, debugMode, MAX_DEBUG_LOG, SKINS_DIR) keep a `local` alias IN EACH FILE that uses them: `local C = Addon.C` etc. They must be assigned on Addon in Init.lua (Addon.C = C or keep the local and add `Addon.C = C` at the end of Init.lua). SIMPLEST CONSISTENT RULE: in Init.lua keep the local declarations, then at the very END of Init.lua emit export lines: `Addon.DebugLog = DebugLog`, `Addon.SafeSetFont = SafeSetFont`, `Addon.trackDialog = trackDialog`, `Addon.CreateStyledFrame = CreateStyledFrame`, `Addon.CreateStyledButton = CreateStyledButton`, `Addon.C = C`, `Addon.MAIN_FONT = MAIN_FONT`, `Addon.BOLD_FONT = BOLD_FONT`, `Addon.debugMode = debugMode`, `Addon.ParseSequenceLines = ParseSequenceLines`, `Addon.BuildKidFriendlyDisplay = BuildKidFriendlyDisplay`, and everything else needed. For pure functions only (immutable), an alias is safe.
- For MUTABLE state, do NOT copy by value anywhere — always `Addon.<name>` at every read AND write.

### B) Functions defined in other modules
- If function `Foo` is used inside its OWN module only → leave as `local function Foo`.
- If `Foo` is used by 2+ modules → in its home module keep `local function Foo`, and at the END of that module add `Addon.Foo = Foo`. In every CONSUMING module add a top-level local alias right after the `local AddonName, Addon = ...` line:
  `local Foo = Addon.Foo`  (this also serves as a self-documenting import list).
  Keep all existing call sites unchanged (they already call `Foo(...)`).
- When a module's function `Foo` internally calls another cross-module function `Bar`, the alias at the top of the consuming file covers it.
- IMPORTANT alias-load caveat: `local Foo = Addon.Foo` at file top requires the HOME module to have been loaded already (Addon.Foo set). The .toc order below guarantees this for every alias. If a circular dependency exists (A.Foo used by B at top-level AND B.Bar used by A at top-level), break it by having ONE side call `Addon.<fn>(...)` at runtime instead of a top-level alias (or defer with a lazy `local function Foo(...) return Addon.Foo(...) end` wrapper). Prefer the lazy wrapper when in doubt — it is ALWAYS load-order-safe.

### C) What to preserve EXACTLY
- Every comment, banner, blank line, and code statement must be copied verbatim (only the namespace/alias edits above).
- `local AddonName, Addon = ...` is the new first line of every file (replace the current first line semantics — the current file IS the whole addon, so it already has this line at line 1; every other file needs it added).
- Do NOT touch: SIMC_SPELL_MAP, ROTATION_EXCLUDE, _validSpellCache, EMS provider registration, IterateSequence, hill-climber caps, GenerateEMSImportString `!DA01!` prefix, ExtractSpellFromSeqLine stripping (interval:N / [dupe]), DamageMeter flow (GetCombatSessionSourceFromType/GetAvailableCombatSessions/GetCombatSessionSourceFromID + pcall guards), health-fallback tracker (TrackTargetHealth / damageFromHealthFallback), LogDisplayName helper, the checkBtn-anchor fix in RefreshSavedLogsList rows (labelText anchored rowFrame TOPLEFT 32,-2 / statText rowFrame BOTTOMLEFT 32,3).
- Global functions assigned today must keep working: Addon.FormatNumber, Addon.ShortNum, Addon.testStartSequence, Addon.bestSequence, Addon.lastActiveSequence, Addon.CompareLogs etc. — verify every existing `Addon.X = ...` assignment in the source survives in the correct module.

### D) WoW globals — leave as-is
C_DamageMeter, C_Spell, C_EncodingUtil, UnitAura, UnitHealth, CreateFrame, C_Timer, issecretvalue, Enum, InCombatLockdown, etc. — all game globals stay untouched references. DummyAnalyzerDB is a SavedVariable global — leave as-is.

## Verification the coder MUST run before reporting back
1. LuaJIT syntax-check EVERY output file:
   `& "C:\Users\Tanner\AppData\Local\Programs\LuaJIT\bin\luajit.exe" -e "assert(loadfile('<file>'))"`
   (path arg with forward slashes or escaped backslashes). All must pass.
2. Grep the whole output dir for any leftover use of a promoted variable that is NOT `Addon.<name>` (esp. testActive, startTime, currentDuration, spellHistory, totalDamage, damageData, currentWindow).
3. Confirm `core.lua` no longer referenced by DummyAnalyzer.toc and the file is removed.
4. Build a symbol report: list for each file (a) exports `Addon.X = X` and (b) imports `local X = Addon.X`. Return this in the final message.

## DummyAnalyzer.toc rewrite (in same dir)
Same metadata as today (## Interface: 120001,120005,120007 / ## Title / ## Notes / ## Author / ## Version: 2.2.0 / ## SavedVariables: DummyAnalyzerDB / ## Dependencies: GRIP-EMS), then ONE line per file in the order given in the table above (Init.lua first, PluginHandshake.lua last).

## Deploy (DO IT)
Copy ALL output .lua files + DummyAnalyzer.toc from
`H:\OPEN CODE WOW CHAT\Wow-Addon\DummyAnalyzer\`
to
`D:\Games\World of Warcraft\_retail_\Interface\AddOns\DummyAnalyzer\`
via PowerShell `Copy-Item -Force`, one per file (or loop). Verify each destination exists with Test-Path.

## Report back
Return: full symbol report (per-file exports/imports), luajit check results (all pass or list of failures), list of deployed files + MD5 of each, and any place you had to use lazy wrappers for circular deps.