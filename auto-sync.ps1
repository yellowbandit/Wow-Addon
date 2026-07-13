# DummyAnalyzer auto-sync: commit + push changes to GitHub
$repo = "H:\OPEN CODE WOW CHAT\Wow-Addon"
$logFile = "$repo\auto-sync.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$errorFlag = "$repo\CONFLICT_FLAG.txt"

Set-Location $repo

# If stuck in a rebase conflict from a previous run, abort and flag it
if (Test-Path "$repo\.git\REBASE_HEAD") {
    git rebase --abort 2>> $logFile
    Add-Content $logFile "[$timestamp] CONFLICT: rebase aborted. Your local changes are preserved. Friend's changes not pulled."
    "CONFLICT at $timestamp - git pull from friend had conflicts. Local files preserved. Friend's changes NOT pulled.
Resolve manually: open terminal in $repo, run: git pull --rebase
Or see auto-sync.log for details." | Set-Content $errorFlag
    exit 1
}

# Try to pull friend's changes
git stash push -m "auto-sync-stash $timestamp" 2>> $logFile
$pullOk = $true
git pull --rebase 2>> $logFile
if (-not $?) {
    git rebase --abort 2>> $logFile
    git stash pop 2>> $logFile
    Add-Content $logFile "[$timestamp] CONFLICT: pull from friend failed. Keeping local changes."
    "CONFLICT at $timestamp - git pull had conflicts. Local files preserved.
Resolve manually: git pull --rebase" | Set-Content $errorFlag
    $pullOk = $false
    exit 1
}
# Re-apply our stashed changes on top of friend's
git stash pop 2>> $logFile
if (-not $?) {
    # Our stash conflicted with friend's changes. Friend's changes are pulled, ours are stashed.
    Add-Content $logFile "[$timestamp] CONFLICT: your local changes conflict with friend's. Stash kept."
    "CONFLICT at $timestamp - your unsaved edits conflict with friend's changes.
Friend's changes are in the folder. Your edits are in the stash.
Resolve: git stash list then git stash pop (fix conflicts manually)." | Set-Content $errorFlag
    exit 1
}

$status = git status --porcelain
if (-not $status) {
    exit 0
}

git add -A 2>> $logFile
git commit -m "auto-sync $timestamp" 2>> $logFile
git push -q 2>> $logFile
Add-Content $logFile "[$timestamp] Pushed $((git rev-parse HEAD).Substring(0,7))"
