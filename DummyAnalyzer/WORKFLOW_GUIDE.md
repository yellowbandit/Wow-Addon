# DummyAnalyzer Workflow Guide

## Setup Overview

```
Your PC (H:\OPEN CODE WOW CHAT\Wow-Addon\DummyAnalyzer\)
  ├── .git           # GitHub repo (yellowbandit/Wow-Addon)
  ├── core.lua       # Edit here
  ├── DummyAnalyzer.toc
  ├── Skins/
  └── auto-sync.ps1  # Runs every 15 min via Task Scheduler

NTFS junctions point here from:
  - H:\OPEN CODE WOW CHAT\DummyAnalyzer\addon\   (AI workspace)
  - D:\Games\World of Warcraft\_retail_\Interface\AddOns\DummyAnalyzer\  (WoW)
```

## Daily Workflow (Your PC)

### Editing + Publishing

1. **Edit files** in `H:\OPEN CODE WOW CHAT\Wow-Addon\DummyAnalyzer\`
   - Changes are live in WoW immediately (junction)
   - Changes are ready for git immediately

2. **Test in WoW** — `/reload` to pick up changes, hit training dummy

3. **Commit + push** — two options:

   **Option A — Git Bash (simple):**
   ```
   cd H:/OPEN CODE WOW CHAT/Wow-Addon
   git add DummyAnalyzer/
   git commit -m "What you changed"
   git push origin main
   ```

   **Option B — VS Code (visual):**
   - Open `H:\OPEN CODE WOW CHAT\Wow-Addon\` in VS Code
   - Click Source Control (Ctrl+Shift+G)
   - Stage changes (➕ icon next to files)
   - Write commit message, click ✔ Commit
   - Click Sync Changes / Push

### Pulling Friend's Changes

1. **VS Code:** Ctrl+Shift+G → ... menu → Pull → Rebase
2. **Git Bash:** `git pull --rebase`
3. **If conflict:** scroll to "Conflict Resolution" below

### Auto-Sync (optional)

Runs every 15 min. Commits local changes, pulls remote changes, pushes.

- **Check status:** Task Scheduler → Task Scheduler Library → DummyAnalyzerAutoSync → check last run
- **Disable:** Task Scheduler → right-click → Disable
- **Enable:** right-click → Enable

## Friend's Workflow (GitHub Website)

1. Fork repo or push branch to anothyer location
2. Create Pull Request targeting `yellowbandit/Wow-Addon`
3. Green check ✓ = no conflicts (you can auto-merge)
4. Red ✗ = conflicts (you need to resolve — see below)
5. You click "Merge pull request" → changes are in `main`

Next time auto-sync runs (or you `git pull --rebase`), you get friend's changes.

## Conflict Resolution (Rare)

### Scenario: You and friend edited the same lines

**Detecting:**
- Auto-sync creates `CONFLICT_FLAG.txt` — you see this file
- `git status` shows `both modified:` files
- `git rebase --status` shows which commit caused conflict

**Resolving:**
```
cd H:/OPEN CODE WOW CHAT/Wow-Addon

# Check what happened
git status

# For each conflicted file, open it and look for:
<<<<<<< HEAD     ← your version
=======          ← divider
>>>>>>> branch   ← friend's version

# Edit to keep what you want, remove the markers, save

# Mark resolved & continue
git add DummyAnalyzer/core.lua   (or whatever file)
git rebase --continue
git push origin main
```

### VS Code conflict resolution (easier):
1. Ctrl+Shift+G shows files with `!` conflict marker
2. Click file → choose "Accept Current" (yours), "Accept Incoming" (theirs), or "Accept Both"
3. Ctrl+Shift+G → continue rebase

### If stuck:
- Auto-sync won't run again until fixed
- Delete `CONFLICT_FLAG.txt` to clear the flag
- `git rebase --skip` to skip the conflicting commit (loses friend's change)
- `git rebase --abort` to cancel and try `git pull --no-rebase` instead

## Changelog

### 2026-09-05 — Damage meter session rollover + timeline caps
- **Fix:** rewritten `ReadDamageMeterData()` — the report now merges all `C_DamageMeter` combat sessions overlapping the test window (legacy `GetCombatSessionSourceFromType` + new `GetSessions()`/`GetPlayerData()`/`GetPartyData()`), fixing reports that showed `Total Dmg: 0` with no damage breakdown after combat ended.
- **Fix:** cast timeline now shows up to **2000** casts in the live report (was 100) and **500** in saved-log view (was 80), removing the `(... more)` truncation.

## GitHub Desktop Setup (one-time)

1. Download from https://desktop.github.com
2. Install, sign in with your GitHub account
3. File → Clone Repository → URL tab → `yellowbandit/Wow-Addon`
4. Choose path: `H:\OPEN CODE WOW CHAT\Wow-Addon`
5. Now you have a visual interface:
   - See changed files (left panel)
   - Write commit message (bottom left)
   - Click "Commit to main"
   - Click "Push origin" (top right)
   - Fetch/Pull to get friend's changes
