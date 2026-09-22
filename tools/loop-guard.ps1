<#
  loop-guard.ps1 -- pipeline circuit breaker / kill switch.

  Why this file exists
  --------------------
  This project runs a three-agent pipeline:
      main agent (writes code)  ->  QA agent (tests)  ->  requirements agent (reviews)
                                       ^                              |
                                       +----------- fix loop ---------+
  Without a hard budget and a shared counter the three sessions can ping-pong
  forever: fix -> retest -> new suggestion -> fix -> retest -> ...
  That burns tokens and machine time while producing no new artifact.

  This script is the MECHANICAL brake. The human-readable rules live in
  AGENTS.md (repo root) and docs/pipeline notes.

  Contract
  --------
  Every agent calls this BEFORE starting a round and AFTER finishing one:

      .\tools\loop-guard.ps1 -Action begin -Feature "feature name" -Stage qa
      .\tools\loop-guard.ps1 -Action end   -Feature "feature name" -Stage qa `
              -Result FAIL -Signature "P0-short-problem-title" -Note "14/16 passed"

  Exit codes:  0 = ALLOW     2 = STOP (halt, report to user, do NOT retry)
               1 = usage error

  Ledger: tools\.pipeline\ledger.tsv  (append-only, tab separated)
          tools\.pipeline\ is the ONE path all three agents may write to.

  NOTE: this file must stay pure ASCII. Windows PowerShell 5.1 decodes
  BOM-less files as GBK; non-ASCII characters here would break parsing.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('begin', 'end', 'status', 'stop', 'ack', 'reset', 'fingerprint')]
    [string]$Action,

    [string]$Feature = 'default',

    [ValidateSet('fix', 'qa', 'review')]
    [string]$Stage = 'qa',

    [ValidateSet('PASS', 'FAIL', 'BLOCKED', 'ENHANCE_THEN_PROCEED', 'PROCEED',
                 'NEED_USER_DECISION', 'HOLD', 'INFO')]
    [string]$Result = 'INFO',

    [string]$Signature = '',
    [string]$Note = '',

    [int]$MaxRoundsPerFeature = 3,
    [int]$MaxReviewRounds = 1,
    [int]$MaxSignatureRepeats = 2,
    [int]$MaxTotalRounds = 40
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$StateDir = Join-Path $PSScriptRoot '.pipeline'
$LedgerPath = Join-Path $StateDir 'ledger.tsv'
$Columns = @('ts', 'feature', 'stage', 'action', 'result', 'fingerprint', 'signature', 'note')
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Clean-Text {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return ($Text -replace "[`t`r`n]", ' ').Trim()
}

function Get-Stamp {
    return (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}

function Read-Ledger {
    if (-not (Test-Path -LiteralPath $LedgerPath)) { return @() }
    $rows = @(Import-Csv -LiteralPath $LedgerPath -Delimiter "`t")
    return @($rows | Where-Object { $_ -and $_.action })
}

function Write-Row {
    param([hashtable]$Row)
    if (-not (Test-Path -LiteralPath $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $LedgerPath)) {
        [System.IO.File]::AppendAllText($LedgerPath, (($Columns -join "`t") + "`r`n"), $Utf8NoBom)
    }
    $cells = @()
    foreach ($col in $Columns) { $cells += (Clean-Text ([string]$Row[$col])) }
    [System.IO.File]::AppendAllText($LedgerPath, (($cells -join "`t") + "`r`n"), $Utf8NoBom)
}

function Get-Fingerprint {
    $roots = @('backend\src', 'backend\pom.xml', 'frontend\src', 'frontend\patient',
               'frontend\admin', 'frontend\package.json', 'db', 'deploy', 'tools')
    $skipDirs = @('node_modules', 'target', 'dist', 'dist-patient', 'dist-admin',
                  'dist-deploy', '.pipeline', 'output', '.git')
    # .md is deliberately absent: editing docs must NOT unlock a retest.
    $exts = @('.java', '.vue', '.js', '.mjs', '.ts', '.json', '.yml', '.yaml', '.sql',
              '.xml', '.ps1', '.sh', '.conf', '.html', '.css', '.properties')

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $roots) {
        $full = Join-Path $ProjectRoot $rel
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $items = @(Get-ChildItem -LiteralPath $full -Recurse -File -Force -ErrorAction SilentlyContinue)
        foreach ($file in $items) {
            $relPath = $file.FullName.Substring($ProjectRoot.Length).TrimStart('\')
            $segments = $relPath.Split('\')
            $blocked = $false
            foreach ($seg in $skipDirs) {
                if ($segments -contains $seg) { $blocked = $true; break }
            }
            if ($blocked) { continue }
            if ($exts -notcontains $file.Extension.ToLower()) { continue }
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            $lines.Add(($relPath.ToLower() + ':' + $hash))
        }
    }

    $blob = [System.Text.Encoding]::UTF8.GetBytes((($lines | Sort-Object) -join "`n"))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $digest = $sha.ComputeHash($blob)
    $text = (($digest | ForEach-Object { $_.ToString('x2') }) -join '')
    return $text.Substring(0, 16)
}

function Stop-Guard {
    param([string]$Reason, [string]$Hint)
    Write-Host ''
    Write-Host '#########################  STOP  #########################'
    Write-Host ("  feature : {0}" -f $Feature)
    Write-Host ("  stage   : {0}" -f $Stage)
    Write-Host ("  reason  : {0}" -f $Reason)
    if ($Hint) { Write-Host ("  next    : {0}" -f $Hint) }
    Write-Host '  Do NOT open another round. Report to the user now.'
    Write-Host '##########################################################'
    Write-Host ''
    exit 2
}

function Show-Status {
    param($Rows)
    # '*' only ever appears on control rows (global stop / ack); it is not a feature.
    $features = @($Rows | Select-Object -ExpandProperty feature -Unique | Where-Object { $_ -and $_ -ne '*' })
    $allowedGlobal = $MaxTotalRounds + (($Rows | Where-Object { $_.action -eq 'ack' -and $_.feature -eq '*' }).Count * $MaxRoundsPerFeature)
    $begins = @($Rows | Where-Object { $_.action -eq 'begin' }).Count

    Write-Host ''
    Write-Host 'loop-guard :: pipeline status'
    Write-Host ("  ledger           : {0}" -f $LedgerPath)
    Write-Host ("  global dispatches: {0} / {1}" -f $begins, $allowedGlobal)
    Write-Host ("  budgets          : fix<= {0}, qa<= {0}, review<= {1}" -f $MaxRoundsPerFeature, $MaxReviewRounds)
    Write-Host ''

    if ($features.Count -eq 0) {
        Write-Host '  (ledger is empty - no rounds recorded yet)'
        Write-Host ''
        return
    }

    $fmt = '  {0,-34} {1,4} {2,4} {3,6}  {4,-22} {5}'
    Write-Host ($fmt -f 'feature', 'fix', 'qa', 'review', 'last result', 'state')
    Write-Host ('  ' + ('-' * 96))

    foreach ($f in $features) {
        $fRows = @($Rows | Where-Object { $_.feature -eq $f })
        $fixN = @($fRows | Where-Object { $_.action -eq 'begin' -and $_.stage -eq 'fix' }).Count
        $qaN = @($fRows | Where-Object { $_.action -eq 'begin' -and $_.stage -eq 'qa' }).Count
        $rvN = @($fRows | Where-Object { $_.action -eq 'begin' -and $_.stage -eq 'review' }).Count
        $lastEnd = $fRows | Where-Object { $_.action -eq 'end' } | Select-Object -Last 1
        $lastResult = ''
        if ($lastEnd) { $lastResult = $lastEnd.result }

        $state = 'open'
        $ctl = $Rows | Where-Object { $_.action -in @('stop', 'ack', 'reset') -and ($_.feature -eq $f -or $_.feature -eq '*') } | Select-Object -Last 1
        if ($ctl -and $ctl.action -eq 'stop') { $state = 'STOPPED' }

        $repeats = @($fRows | Where-Object { $_.action -eq 'end' -and $_.result -eq 'FAIL' -and $_.signature } |
                     Group-Object signature | Where-Object { $_.Count -ge $MaxSignatureRepeats })
        if ($repeats.Count -gt 0) { $state = 'REPEAT:' + $repeats[0].Name }

        Write-Host ($fmt -f $f, $fixN, $qaN, $rvN, $lastResult, $state)
    }
    Write-Host ''
}

function Get-ExtraRounds {
    param($Rows, [string]$FeatureName)
    $grants = @($Rows | Where-Object { $_.action -eq 'ack' -and ($_.feature -eq $FeatureName -or $_.feature -eq '*') }).Count
    return ($grants * $MaxRoundsPerFeature)
}

function Get-LastAck {
    param($Rows, [string]$FeatureName)
    return ($Rows | Where-Object { $_.action -eq 'ack' -and ($_.feature -eq $FeatureName -or $_.feature -eq '*') } | Select-Object -Last 1)
}

# Timestamps use 'yyyy-MM-dd HH:mm:ss', so string comparison is chronological.
function Test-AuthorisedAfter {
    param($Ack, [string]$Stamp)
    if (-not $Ack) { return $false }
    return ([string]$Ack.ts -ge [string]$Stamp)
}

# ---------------------------------------------------------------- main

$rows = Read-Ledger

if ($Action -eq 'status') {
    Show-Status -Rows $rows
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Feature)) {
    Write-Host 'loop-guard: -Feature must not be empty.'
    exit 1
}
$Feature = Clean-Text $Feature

if ($Action -eq 'fingerprint') {
    $fp = Get-Fingerprint
    $previous = $rows | Where-Object { $_.feature -eq $Feature -and $_.fingerprint } | Select-Object -Last 1
    Write-Host ("fingerprint : {0}" -f $fp)
    if ($previous) {
        Write-Host ("last round  : {0} ({1}/{2})" -f $previous.fingerprint, $previous.stage, $previous.result)
        if ($previous.fingerprint -eq $fp) {
            Write-Host 'changed     : NO  (same source tree as the last round - a retest would be pure waste)'
        } else {
            Write-Host 'changed     : YES (source tree differs from the last round)'
        }
    } else {
        Write-Host 'changed     : (no previous round recorded for this feature)'
    }
    Write-Host ''
    Write-Row @{ ts = (Get-Stamp); feature = $Feature; stage = $Stage; action = 'fingerprint'
                 result = ''; fingerprint = $fp; signature = ''; note = (Clean-Text $Note) }
    exit 0
}

if ($Action -eq 'stop') {
    $stopNote = $Note
    if ([string]::IsNullOrWhiteSpace($stopNote)) { $stopNote = 'manual kill switch' }
    Write-Row @{ ts = (Get-Stamp); feature = $Feature; stage = $Stage; action = 'stop'
                 result = ''; fingerprint = ''; signature = ''
                 note = (Clean-Text $stopNote) }
    Write-Host ''
    Write-Host ("loop-guard: STOPPED feature '{0}'." -f $Feature)
    Write-Host ("  reason: {0}" -f (Clean-Text $stopNote))
    Write-Host '  All agents must halt. Only the user can lift this with -Action ack.'
    Write-Host ''
    exit 2
}

if ($Action -eq 'ack') {
    if ([string]::IsNullOrWhiteSpace($Note)) {
        Write-Host 'loop-guard: -Action ack requires -Note "who authorised this and why".'
        Write-Host '  The circuit breaker is only lifted by an explicit user decision.'
        exit 1
    }
    Write-Row @{ ts = (Get-Stamp); feature = $Feature; stage = $Stage; action = 'ack'
                 result = ''; fingerprint = ''; signature = ''; note = (Clean-Text $Note) }
    Write-Host ''
    Write-Host ("loop-guard: unlocked '{0}'. Extra budget = {1} rounds per stage." -f $Feature, $MaxRoundsPerFeature)
    Write-Host ("  note: {0}" -f (Clean-Text $Note))
    Write-Host ''
    exit 0
}

if ($Action -eq 'reset') {
    $resetNote = $Note
    if ([string]::IsNullOrWhiteSpace($resetNote)) { $resetNote = 'counter reset' }
    Write-Row @{ ts = (Get-Stamp); feature = $Feature; stage = $Stage; action = 'reset'
                 result = ''; fingerprint = ''; signature = ''
                 note = (Clean-Text $resetNote) }
    Write-Host ("loop-guard: counters for '{0}' reset (history kept in the ledger)." -f $Feature)
    exit 0
}

if ($Action -eq 'begin') {
    $featRows = @($rows | Where-Object { $_.feature -eq $Feature })

    # R1: manual / automatic kill switch
    $ctl = $rows | Where-Object { $_.action -in @('stop', 'ack', 'reset') -and ($_.feature -eq $Feature -or $_.feature -eq '*') } | Select-Object -Last 1
    if ($ctl -and $ctl.action -eq 'stop') {
        Stop-Guard -Reason ("circuit breaker is ENGAGED: {0} (at {1})" -f $ctl.note, $ctl.ts) `
                   -Hint 'ask the user to authorise more work, then: -Action ack -Feature "<name>" -Note "<decision>"'
    }

    # R2: project-wide budget
    $globalGrant = ($rows | Where-Object { $_.action -eq 'ack' -and $_.feature -eq '*' }).Count * $MaxRoundsPerFeature
    $begins = @($rows | Where-Object { $_.action -eq 'begin' }).Count
    if ($begins -ge ($MaxTotalRounds + $globalGrant)) {
        Stop-Guard -Reason ("project-wide dispatch budget exhausted ({0}/{1})" -f $begins, ($MaxTotalRounds + $globalGrant)) `
                   -Hint 'review the ledger, report progress to the user, ask before continuing'
    }

    # R3: the previous round of this stage was never closed
    $stageRows = @($featRows | Where-Object { $_.stage -eq $Stage })
    $lastStageRow = $stageRows | Select-Object -Last 1
    if ($lastStageRow -and $lastStageRow.action -eq 'begin') {
        Stop-Guard -Reason ("the previous '{0}' round was never closed - no result was reported" -f $Stage) `
                   -Hint ("register it first: -Action end -Feature ""{0}"" -Stage {1} -Result PASS|FAIL|BLOCKED" -f $Feature, $Stage)
    }

    # R4: per-stage round cap
    $extra = Get-ExtraRounds -Rows $rows -FeatureName $Feature
    $used = @($stageRows | Where-Object { $_.action -eq 'begin' }).Count
    $cap = $MaxRoundsPerFeature + $extra
    if ($Stage -eq 'review') { $cap = $MaxReviewRounds + $extra }
    if ($used -ge $cap) {
        Stop-Guard -Reason ("'{0}' has already run {1} round(s) for this feature (cap {2})" -f $Stage, $used, $cap) `
                   -Hint 'per-feature budget reached - report to the user instead of looping again'
    }

    # R5: the same problem keeps coming back -> the fix is not working.
    # An explicit user decision (ack) recorded AFTER the last failure lifts this.
    $lastAck = Get-LastAck -Rows $rows -FeatureName $Feature
    $repeats = @($featRows | Where-Object { $_.action -eq 'end' -and $_.result -eq 'FAIL' -and $_.signature } |
                 Group-Object signature | Where-Object { $_.Count -ge $MaxSignatureRepeats })
    $blocking = @()
    foreach ($grp in $repeats) {
        $lastFail = $grp.Group | Select-Object -Last 1
        if (-not (Test-AuthorisedAfter -Ack $lastAck -Stamp $lastFail.ts)) { $blocking += $grp.Name }
    }
    if ($blocking.Count -gt 0) {
        $names = $blocking -join ' | '
        Stop-Guard -Reason ("the same problem was reported {0} times: {1}" -f $MaxSignatureRepeats, $names) `
                   -Hint 'the earlier fix did not work - escalate to the user, do not retry again'
    }
    if ($repeats.Count -gt 0) {
        Write-Host ("[loop-guard] WARNING: '{0}' has already failed {1} time(s) - proceeding only because the user authorised it." -f `
                    (($repeats | ForEach-Object { $_.Name }) -join ' | '), $MaxSignatureRepeats)
    }

    # R6: retesting an unchanged source tree after a FAIL.
    # Only fires when the previous QA round FAILED and nothing in the tree moved since:
    # that is the classic "main agent claims it is fixed, but no file changed" loop.
    # A BLOCKED round (missing password / environment) may legitimately be re-run.
    $fp = Get-Fingerprint
    if ($Stage -eq 'qa') {
        $lastQaEnd = $featRows | Where-Object { $_.stage -eq 'qa' -and $_.action -eq 'end' } | Select-Object -Last 1
        if ($lastQaEnd -and $lastQaEnd.result -eq 'FAIL' -and $lastQaEnd.fingerprint -eq $fp) {
            if (-not (Test-AuthorisedAfter -Ack $lastAck -Stamp $lastQaEnd.ts)) {
                Stop-Guard -Reason ("QA failed on this exact source tree ({0}) and nothing changed since - retesting would be pure waste" -f $fp) `
                           -Hint 'fix the source first; if no fix is needed, tell the user and stop the pipeline'
            }
        }
    }

    # R7: single-track pipeline. Another feature/stage still has an open round,
    # which means two agents are writing the same tree at the same time.
    # NOTE: group by the real columns - do NOT build a "a || b" key and split it,
    # because PowerShell turns Split('||') into Split(@('|','|')) and the index shifts.
    $openRounds = @()
    $pairs = @($rows | Where-Object { $_.action -eq 'begin' -or $_.action -eq 'end' } |
               Group-Object -Property feature, stage)
    foreach ($pair in $pairs) {
        $lastRow = $pair.Group | Select-Object -Last 1
        if (-not $lastRow) { continue }
        if ($lastRow.action -ne 'begin') { continue }
        if ($lastRow.feature -eq $Feature -and $lastRow.stage -eq $Stage) { continue }
        $openRounds += ("{0} / {1}" -f $lastRow.feature, $lastRow.stage)
    }
    if ($openRounds.Count -gt 0) {
        Stop-Guard -Reason ("another round is still open: {0}" -f ($openRounds -join ' | ')) `
                   -Hint 'the pipeline is single-track - close that round first, or two agents will fight over the same files'
    }

    Write-Row @{ ts = (Get-Stamp); feature = $Feature; stage = $Stage; action = 'begin'
                 result = ''; fingerprint = $fp; signature = ''; note = (Clean-Text $Note) }

    Write-Host ''
    Write-Host ('[loop-guard] ALLOW  feature={0}  stage={1}  round={2}/{3}  fingerprint={4}' -f `
                $Feature, $Stage, ($used + 1), $cap, $fp)
    Write-Host ("             global dispatches: {0}/{1}" -f ($begins + 1), ($MaxTotalRounds + $globalGrant))
    Write-Host ''
    exit 0
}

if ($Action -eq 'end') {
    $stageRows = @($rows | Where-Object { $_.feature -eq $Feature -and $_.stage -eq $Stage })
    $lastStageRow = $stageRows | Select-Object -Last 1
    if (-not $lastStageRow -or $lastStageRow.action -ne 'begin') {
        Write-Host ("loop-guard: no open '{0}' round for '{1}' - call -Action begin first." -f $Stage, $Feature)
        exit 1
    }
    if ($Result -eq 'INFO') {
        Write-Host 'loop-guard: -Action end requires -Result PASS|FAIL|BLOCKED|...'
        exit 1
    }

    $fp = $lastStageRow.fingerprint
    if ($Result -eq 'FAIL' -and [string]::IsNullOrWhiteSpace($Signature)) {
        Write-Host 'loop-guard: WARNING - a FAIL without -Signature cannot be de-duplicated.'
        Write-Host '            Use a short stable title, e.g. -Signature "P0-patient-token-can-call-staff-api"'
    }

    Write-Row @{ ts = (Get-Stamp); feature = $Feature; stage = $Stage; action = 'end'
                 result = $Result; fingerprint = $fp; signature = (Clean-Text $Signature)
                 note = (Clean-Text $Note) }

    Write-Host ''
    Write-Host ('[loop-guard] recorded  feature={0}  stage={1}  result={2}  signature={3}' -f `
                $Feature, $Stage, $Result, (Clean-Text $Signature))

    if ($Result -eq 'FAIL') {
        $sig = Clean-Text $Signature
        $count = @($rows | Where-Object { $_.feature -eq $Feature -and $_.action -eq 'end' -and $_.result -eq 'FAIL' -and $_.signature -eq $sig }).Count + 1
        if ($sig -and $count -ge $MaxSignatureRepeats) {
            Write-Row @{ ts = (Get-Stamp); feature = $Feature; stage = $Stage; action = 'stop'
                         result = ''; fingerprint = ''; signature = $sig
                         note = ("same problem reported {0} times: {1}" -f $count, $sig) }
            Write-Host ''
            Write-Host '#########################  STOP  #########################'
            Write-Host ("  the same problem came back {0} times: {1}" -f $count, $sig)
            Write-Host '  The circuit breaker is now ENGAGED. All agents must halt.'
            Write-Host '  Report to the user: what was tried, what still fails, what you need.'
            Write-Host '  Only the user can lift this:  -Action ack -Feature "<name>" -Note "<decision>"'
            Write-Host '##########################################################'
            Write-Host ''
            exit 2
        }
        Write-Host ("            FAIL #{0} for this signature (breaker trips at {1})" -f $count, $MaxSignatureRepeats)
    }
    Write-Host ''
    exit 0
}
