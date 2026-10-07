<#
.SYNOPSIS
  Re-attach Claude Code (desktop app) sessions from other accounts to the account you are using now.

.DESCRIPTION
  On one Windows user, chat transcripts and project memory live in  ~\.claude\projects  and are shared by
  every Claude account. The desktop app's session LIST, however, is stored per account in
  %APPDATA%\Claude\claude-code-sessions\<accountId>\<orgId>\local_*.json  - so after switching account the
  sidebar looks empty even though nothing was lost.

  This script copies those local_*.json index files from the other accounts into the active account.
  It only ADDS files: nothing is edited or deleted, files that already exist are skipped.
  Default mode is a dry run. The active account is read from the app's config (lastKnownAccountUuid).

  ONE CLICK:  double-click  Sync-Claude-Sessions.bat   (runs with -OneClick)
  UNDO:       double-click  Undo-Sync-Claude-Sessions.bat   (runs with -Undo)

.PARAMETER OneClick
  Whole flow: show plan, ask Y/N, close the Claude desktop app, back up, copy, reopen the app.

.PARAMETER Undo
  Remove the session files copied by the most recent run (from logs\copied-*.log).

.PARAMETER Yes
  Do not ask for confirmation (with -OneClick / -Undo).

.PARAMETER TargetAccount
  Override the target account (folder name or prefix). Default: lastKnownAccountUuid from the app config.

.PARAMETER TargetOrg
  Org folder (prefix) inside the target account. Default: the org with the newest session.

.PARAMETER SourceAccount
  Only copy from these account folders (prefixes). Default: every account other than the target.

.PARAMETER BackupDir
  With -Apply or -BackupOnly: write a timestamped backup of ~\.claude\projects and claude-code-sessions here.

.PARAMETER Apply
  Copy for real, without the automatic close/reopen of the app (the app must already be closed).

.PARAMETER BackupOnly
  Only make the backup (needs -BackupDir) and exit.

.PARAMETER Force
  With -Apply: continue even if a Claude process is running (not recommended).
#>
[CmdletBinding()]
param(
  [switch]$OneClick,
  [switch]$Undo,
  [switch]$Yes,
  [string]$TargetAccount,
  [string]$TargetOrg,
  [string[]]$SourceAccount,
  [string]$BackupDir,
  [switch]$Apply,
  [switch]$BackupOnly,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# The desktop app is an MSIX (Store) package, so its "%APPDATA%\Claude" is redirected into the package folder.
# Only processes running inside the app see that redirect; from File Explorer the real files are here:
#   %LOCALAPPDATA%\Packages\Claude_<id>\LocalCache\Roaming\Claude
function Resolve-ClaudeDataRoot {
  $cands = @()
  $pk = Join-Path $env:LOCALAPPDATA 'Packages'
  if (Test-Path -LiteralPath $pk) {
    $cands += @(Get-ChildItem -LiteralPath $pk -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
      ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Claude' })
  }
  $cands += (Join-Path $env:APPDATA 'Claude')
  foreach ($c in $cands) { if (Test-Path -LiteralPath (Join-Path $c 'claude-code-sessions')) { return $c } }
  throw ('Claude data folder not found. Looked in: ' + ($cands -join '; '))
}
try { $dataRoot = Resolve-ClaudeDataRoot }
catch { Write-Host ''; Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }

$sessionsRoot = Join-Path $dataRoot 'claude-code-sessions'
$configPath   = Join-Path $dataRoot 'config.json'
$projectsRoot = Join-Path $env:USERPROFILE '.claude\projects'
$logDir       = Join-Path $PSScriptRoot 'logs'

# ---- helpers ----------------------------------------------------------------------------------------------
function Get-ClaudeProcs {
  # the desktop app (MSIX install) and the CLI binary it manages; a CLI you started yourself is left alone
  @(Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -like '*\WindowsApps\Claude_*' -or $_.Path -like '*\Claude\claude-code\*'
  })
}

function Test-InsideClaude {
  $id = $PID
  for ($i = 0; $i -lt 25 -and $id; $i++) {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    if ($p.ExecutablePath -like '*\WindowsApps\Claude_*' -or $p.ExecutablePath -like '*\Claude\claude-code\*') { return $true }
    $id = $p.ParentProcessId
  }
  return $false
}

function Stop-ClaudeDesktop {
  $procs = Get-ClaudeProcs
  if ($procs.Count -eq 0) { return $false }
  foreach ($p in $procs) { if ($p.MainWindowHandle -ne 0) { [void]$p.CloseMainWindow() } }
  $deadline = (Get-Date).AddSeconds(8)
  while ((Get-Date) -lt $deadline -and (Get-ClaudeProcs).Count -gt 0) { Start-Sleep -Milliseconds 500 }
  foreach ($p in (Get-ClaudeProcs)) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch {} }
  Start-Sleep -Seconds 2
  if ((Get-ClaudeProcs).Count -gt 0) { throw 'Could not close the Claude desktop app. Close it by hand and run again.' }
  return $true
}

function Start-ClaudeDesktop {
  $id = 'Claude_pzs8sxrjxfjjc!Claude'
  try { $a = Get-StartApps | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1; if ($a) { $id = $a.AppID } } catch {}
  Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\' + $id)
}

function Restart-ClaudeDesktop([string]$okMessage) {
  try { Start-ClaudeDesktop; Write-Host $okMessage }
  catch { Write-Host 'Could not reopen Claude automatically - start it from the Start menu.' }
}

function Get-ActiveAccountId {
  if (-not (Test-Path -LiteralPath $configPath)) { return $null }
  $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
  return [string]$cfg.lastKnownAccountUuid
}

function Copy-Tree([string]$src, [string]$dst) {
  & robocopy $src $dst /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE) for $src" }
}

function Backup-ClaudeData([string]$dest) {
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Tree $projectsRoot (Join-Path $dest 'projects')
  Copy-Tree $sessionsRoot (Join-Path $dest 'claude-code-sessions')
  return $dest
}

function Select-OrgDir($acctDir, [string]$orgPrefix) {
  $orgs = @(Get-ChildItem -LiteralPath $acctDir.FullName -Directory)
  if ($orgPrefix) { $orgs = @($orgs | Where-Object { $_.Name -like "$orgPrefix*" }) }
  if ($orgs.Count -eq 0) { throw 'No matching org folder inside the target account.' }
  foreach ($filter in @('local_*.json', '*')) {
    $best = $null; $bestTime = [datetime]::MinValue
    foreach ($o in $orgs) {
      $f = Get-ChildItem -LiteralPath $o.FullName -File -Filter $filter -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
      if ($f -and $f.LastWriteTime -gt $bestTime) { $best = $o; $bestTime = $f.LastWriteTime }
    }
    if ($best) { return $best.FullName }
  }
  return $orgs[0].FullName
}

function Confirm-OrExit([string]$question) {
  if ($Yes) { return $true }
  $a = Read-Host $question
  return ($a -match '^(y|yes)$')
}

function Invoke-Main {
  foreach ($p in @($sessionsRoot, $projectsRoot)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Not found: $p" }
  }

  if ($BackupOnly) {
    if (-not $BackupDir) { throw '-BackupOnly needs -BackupDir' }
    Write-Host ('Backup written to: ' + (Backup-ClaudeData (Join-Path $BackupDir ('claude-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))))
    return
  }

  # ---- undo -----------------------------------------------------------------------------------------------
  if ($Undo) {
    $last = Get-ChildItem -LiteralPath $logDir -Filter 'copied-*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $last) { Write-Host 'No sync log found - nothing to undo.'; return }
    $files = @(Get-Content -LiteralPath $last.FullName -Encoding UTF8 | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    $files = @($files | Where-Object { $_.StartsWith($sessionsRoot, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $_ -Leaf) -like 'local_*.json' })
    Write-Host ('Undo the sync from log ' + $last.Name + ':')
    foreach ($f in $files) { Write-Host ('  remove ' + $f) }
    if ($files.Count -eq 0) { Write-Host '  (those files are already gone)'; Rename-Item -LiteralPath $last.FullName -NewName ($last.Name + '.undone'); return }
    if (-not (Confirm-OrExit 'Type Y and press Enter to remove them (the Claude desktop app will be closed and reopened)')) { Write-Host 'Cancelled. Nothing was changed.'; return }
    if (Test-InsideClaude) { throw 'Run this by double-clicking the .bat file in File Explorer, not from inside the Claude app.' }
    $wasRunning = Stop-ClaudeDesktop
    foreach ($f in $files) { Remove-Item -LiteralPath $f }
    Rename-Item -LiteralPath $last.FullName -NewName ($last.Name + '.undone')
    Write-Host ('Removed {0} file(s).' -f $files.Count)
    if ($wasRunning) { Restart-ClaudeDesktop 'Claude desktop reopened.' }
    return
  }

  # ---- inventory ------------------------------------------------------------------------------------------
  $sessions = @(Get-ChildItem -LiteralPath $sessionsRoot -Recurse -File -Filter 'local_*.json' | ForEach-Object {
    $parts = $_.FullName.Substring($sessionsRoot.Length).TrimStart('\').Split('\')
    [pscustomobject]@{ File = $_; Account = $parts[0]; Org = $parts[1]; Name = $_.Name }
  })
  $accountDirs = @(Get-ChildItem -LiteralPath $sessionsRoot -Directory)

  Write-Host 'Accounts found:'
  foreach ($a in $accountDirs) {
    $mine = @($sessions | Where-Object { $_.Account -eq $a.Name })
    $last = ''
    if ($mine.Count -gt 0) { $last = ($mine | Sort-Object { $_.File.LastWriteTime } -Descending | Select-Object -First 1).File.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
    Write-Host ('  {0}  sessions={1}  last={2}' -f $a.Name, $mine.Count, $last)
  }

  # ---- target account ---------------------------------------------------------------------------------------
  $how = ''
  $wanted = $TargetAccount
  if ($wanted) { $how = '(from -TargetAccount)' }
  else {
    $wanted = Get-ActiveAccountId
    if ($wanted) { $how = '(active account, from the app config)' }
  }
  if ($wanted) {
    $hit = @($accountDirs | Where-Object { $_.Name -like "$wanted*" })
    if ($hit.Count -ne 1) { throw "Account '$wanted' has no session folder yet (matched $($hit.Count)). Open the Code tab once in the app with that account, then run again." }
    $targetAcct = $hit[0]
  } else {
    if ($Apply -or $OneClick) { throw 'Cannot tell which account is active. Pass -TargetAccount <id>.' }
    if ($sessions.Count -eq 0) { throw 'No sessions found at all.' }
    $newest = $sessions | Sort-Object { $_.File.LastWriteTime } -Descending | Select-Object -First 1
    $targetAcct = $accountDirs | Where-Object { $_.Name -eq $newest.Account }
    $how = '(GUESSED from newest session - verify!)'
  }
  $targetDir = Select-OrgDir $targetAcct $TargetOrg
  Write-Host ''
  Write-Host ('Target: {0}\{1}  {2}' -f $targetAcct.Name, (Split-Path $targetDir -Leaf), $how)

  # ---- plan -------------------------------------------------------------------------------------------------
  $have = @{}
  foreach ($s in ($sessions | Where-Object { $_.Account -eq $targetAcct.Name })) { $have[$s.Name] = $true }

  $transcripts = @{}
  foreach ($d in (Get-ChildItem -LiteralPath $projectsRoot -Directory)) {
    foreach ($f in (Get-ChildItem -LiteralPath $d.FullName -Filter '*.jsonl' -File)) { $transcripts[$f.BaseName] = $f.FullName }
  }

  $sources = @($sessions | Where-Object { $_.Account -ne $targetAcct.Name })
  if ($SourceAccount) {
    $sources = @($sources | Where-Object { $acc = $_.Account; @($SourceAccount | Where-Object { $acc -like "$_*" }).Count -gt 0 })
  }

  $plan = @(foreach ($s in $sources) {
    $j = Get-Content -LiteralPath $s.File.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $status = 'COPY'
    if ($have.ContainsKey($s.Name)) { $status = 'SKIP (already in target)' }
    elseif (-not $j.cliSessionId -or -not $transcripts.ContainsKey([string]$j.cliSessionId)) { $status = 'SKIP (transcript missing)' }
    [pscustomobject]@{
      Status = $status; Title = $j.title; Cwd = $j.cwd
      CwdExists = (Test-Path -LiteralPath ([string]$j.cwd)); From = $s.Account.Substring(0, 8)
      Src = $s.File.FullName; Dest = (Join-Path $targetDir $s.Name)
    }
  })

  Write-Host ''
  if ($plan.Count -eq 0) { Write-Host 'Nothing to do: no sessions in other accounts.'; return }
  ($plan | Select-Object Status, Title, Cwd, CwdExists, From | Format-Table -AutoSize | Out-String -Width 220) | Write-Host
  $todo = @($plan | Where-Object { $_.Status -eq 'COPY' })
  Write-Host ('{0} to copy, {1} skipped.' -f $todo.Count, ($plan.Count - $todo.Count))

  if (-not $Apply -and -not $OneClick) {
    Write-Host ''
    Write-Host 'DRY RUN - nothing was changed. For the one-click flow, double-click Sync-Claude-Sessions.bat'
    return
  }
  if ($todo.Count -eq 0) { Write-Host 'Everything is already synced.'; return }

  # ---- apply ------------------------------------------------------------------------------------------------
  $backupDest = $null
  $wasRunning = $false
  if ($OneClick) {
    if (-not (Confirm-OrExit 'Type Y and press Enter to continue (the Claude desktop app will be closed and reopened - save your work first)')) {
      Write-Host 'Cancelled. Nothing was changed.'; return
    }
    if (Test-InsideClaude) { throw 'Run this by double-clicking the .bat file in File Explorer, not from inside the Claude app.' }
    $backupDest = Join-Path $PSScriptRoot 'backup'
    Write-Host 'Closing Claude desktop ...'
    $wasRunning = Stop-ClaudeDesktop
  } else {
    if ((Get-ClaudeProcs).Count -gt 0 -and -not $Force) {
      throw 'A Claude process is running. Close the desktop app (also from the tray) and retry, or use -OneClick.'
    }
    if ($BackupDir) { $backupDest = Join-Path $BackupDir ('claude-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
  }

  if ($backupDest) { Write-Host 'Backing up chats and session list ...'; Write-Host ('Backup written to: ' + (Backup-ClaudeData $backupDest)) }

  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $log = Join-Path $logDir ('copied-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
  foreach ($p in $todo) {
    Copy-Item -LiteralPath $p.Src -Destination $p.Dest
    if (-not (Test-Path -LiteralPath $p.Dest)) { throw "Copy failed: $($p.Dest)" }
    $null = Get-Content -LiteralPath $p.Dest -Raw -Encoding UTF8 | ConvertFrom-Json   # must still parse
    Add-Content -LiteralPath $log -Value $p.Dest -Encoding UTF8
  }
  Write-Host ''
  Write-Host ('Copied {0} session file(s).' -f $todo.Count)
  if ($OneClick) {
    if ($wasRunning) { Restart-ClaudeDesktop 'Claude desktop reopened - the old sessions should now be in the sidebar.' }
    else { Write-Host 'Start Claude desktop - the old sessions should now be in the sidebar.' }
    Write-Host 'Not what you wanted? Double-click Undo-Sync-Claude-Sessions.bat'
  } else {
    Write-Host ('Start Claude desktop. To undo, run with -Undo (log: ' + $log + ')')
  }
}

try { Invoke-Main }
catch {
  Write-Host ''
  Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
