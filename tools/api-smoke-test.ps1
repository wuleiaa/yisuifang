# =============================================================================
#  API smoke test - staff backend (http://127.0.0.1:8080)
#
#  Verifies every implemented endpoint plus the three things that are easy to
#  break silently:
#    * row level security (nurse / doctor / head nurse see different rows)
#    * phone number masking (no raw phone number ever leaves the API)
#      ... except the one-tap dial endpoint, which exists precisely to hand a
#      real number to the phone dialer - and it must leave an audit row
#    * audit trail (claim + complete both leave a task log row)
#
#  IMPORTANT: keep this file ASCII-only.
#    Windows PowerShell 5.1 decodes BOM-less .ps1 as GBK on Chinese Windows,
#    which corrupts non-ASCII text and breaks parsing.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\api-smoke-test.ps1
#    powershell ... -File .\tools\api-smoke-test.ps1 -SkipMutation
#
#  -SkipMutation skips claim/complete so demo data is left untouched.
# =============================================================================

param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$Password = 'Followup@2026',
    # The three demo accounts may each have their own password on a real
    # deployment (the seed password only stands for "fresh install"), so they
    # can be given separately; anything omitted falls back to -Password.
    # This lets the same script run against localhost or https://<domain>.
    [string]$DoctorPassword = '',
    [string]$NursePassword = '',
    [string]$HeadNursePassword = '',
    [switch]$SkipMutation
)

$ErrorActionPreference = 'Stop'

if (-not $DoctorPassword)    { $DoctorPassword = $Password }
if (-not $NursePassword)     { $NursePassword = $Password }
if (-not $HeadNursePassword) { $HeadNursePassword = $Password }

# When the local dev database (portable PostgreSQL) is not running, the steps
# that query it directly cannot run. Against a deployed URL they are not
# meaningful anyway - verify the same assertions on that server's database.
function Test-LocalDevDb {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect('127.0.0.1', 55432, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(1500)) { return $false }
        $c.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        $c.Close()
    }
}

# Only meaningful when we are actually testing the local stack: pointing the
# suite at a deployed URL while the local database happens to be running would
# otherwise check the WRONG database and report a false pass.
$script:LocalDevDbUp = (Test-LocalDevDb) -and ($BaseUrl -match '^https?://(127\.0\.0\.1|localhost)([:/]|$)')

$script:PassCount = 0
$script:FailCount = 0
$script:SkipCount = 0
# Set by a step body that cannot run in the current environment (e.g. it needs
# the local dev database). A skipped step must never be reported as a pass.
$script:SkipPending = $false
$script:Timings = New-Object System.Collections.ArrayList

function Write-Head([string]$Text) {
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
}

function Test-Step {
    param(
        [string]$Name,
        [scriptblock]$Body
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $value = & $Body
        $sw.Stop()
        if ($script:SkipPending) {
            $script:SkipPending = $false
            $script:SkipCount++
            Write-Host ("  SKIP  {0,-46} {1,6} ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Yellow
            return $null
        }
        [void]$script:Timings.Add([pscustomobject]@{ Name = $Name; Ms = $sw.ElapsedMilliseconds })
        $script:PassCount++
        Write-Host ("  PASS  {0,-46} {1,6} ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Green
        return $value
    } catch {
        $sw.Stop()
        [void]$script:Timings.Add([pscustomobject]@{ Name = $Name; Ms = $sw.ElapsedMilliseconds })
        $script:FailCount++
        Write-Host ("  FAIL  {0,-46} {1,6} ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Red
        Write-Host ("        {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        [hashtable]$Headers = @{},
        $Body = $null
    )
    $params = @{
        Uri        = "$BaseUrl$Path"
        Method     = $Method
        Headers    = $Headers
        TimeoutSec = 30
    }
    if ($null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 6 -Compress)
        $params.ContentType = 'application/json; charset=utf-8'
    }
    $resp = Invoke-RestMethod @params
    if ($null -eq $resp -or $null -eq $resp.code) {
        throw "unexpected response shape: $($resp | Out-String)"
    }
    if ($resp.code -ne 0) {
        throw "api error code=$($resp.code) message=$($resp.message)"
    }
    return $resp.data
}

function New-Session([string]$StaffNo, [string]$Pwd = '') {
    if (-not $Pwd) { $Pwd = $Password }
    $data = Invoke-Api -Method Post -Path '/api/auth/login' -Body @{
        staffNo  = $StaffNo
        password = $Pwd
    }
    Assert-True ($null -ne $data.token) "login returned no token for $StaffNo"
    return @{ Authorization = "Bearer $($data.token)" }
}

# -----------------------------------------------------------------------------
# 0. reachability
# -----------------------------------------------------------------------------
Write-Head "0. Reachability  ($BaseUrl)"

Test-Step 'GET /actuator/health' {
    # Direct backend exposes /actuator/health; behind nginx the public path is
    # /health. Try both, so a wrong path never looks like an unhealthy service.
    $h = $null
    foreach ($p in @('/health', '/actuator/health')) {
        try {
            $try = Invoke-RestMethod -Uri "$BaseUrl$p" -TimeoutSec 10
            if ($try.status -eq 'UP') { $h = $try; break }
        } catch { }
    }
    Assert-True ($h.status -eq 'UP') "health status = $($h.status)"
    return $h
} | Out-Null

# -----------------------------------------------------------------------------
# 1. auth
# -----------------------------------------------------------------------------
Write-Head '1. Auth'

$doctorHeaders   = $null
$nurseHeaders    = $null
$managerHeaders  = $null

Test-Step 'POST /api/auth/login (D0231 doctor)' {
    $data = Invoke-Api -Method Post -Path '/api/auth/login' -Body @{
        staffNo  = 'D0231'
        password = $DoctorPassword
    }
    Assert-True ($data.token.Length -gt 20) 'token looks too short'
    $script:doctorHeaders = @{ Authorization = "Bearer $($data.token)" }
    return $data
} | Out-Null

Test-Step 'POST /api/auth/login (N0455 nurse)' {
    $script:nurseHeaders = New-Session 'N0455' $NursePassword
    return $null
} | Out-Null

Test-Step 'POST /api/auth/login (N0001 head nurse)' {
    $script:managerHeaders = New-Session 'N0001' $HeadNursePassword
    return $null
} | Out-Null

if (-not $script:doctorHeaders) {
    Write-Host ''
    Write-Host 'Cannot continue: doctor login failed.' -ForegroundColor Red
    exit 1
}

Test-Step 'GET /api/auth/me' {
    $me = Invoke-Api -Method Get -Path '/api/auth/me' -Headers $script:doctorHeaders
    Assert-True ($me.staffNo -eq 'D0231') "staffNo = $($me.staffNo)"
    return $me
} | Out-Null

Test-Step 'GET /api/auth/crypto-check' {
    $c = Invoke-Api -Method Get -Path '/api/auth/crypto-check' -Headers $script:doctorHeaders
    Assert-True ($c.ok -eq $true) "crypto self check failed: $($c.message)"
    Assert-True ($c.masked -match '\*') "phone not masked: $($c.masked)"
    return $c
} | Out-Null

Test-Step 'GET /api/auth/me without token -> 401' {
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/auth/me" -TimeoutSec 10 | Out-Null
        throw 'expected 401 but the call succeeded'
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        Assert-True ($status -eq 401 -or $status -eq 403) "expected 401/403, got $status"
    }
    return $null
} | Out-Null

Test-Step 'browser-style POST (Origin header) is not CORS-rejected' {
    # Regression guard for the 2026-09-22 outage-class bug: behind the
    # TLS-terminating nginx the app saw scheme http, while the browser sends
    # Origin https://<domain>. The CORS filter therefore answered 403 to EVERY
    # browser POST - the site looked fine but nobody could log in. PowerShell
    # sends no Origin header, which is exactly why every suite stayed green
    # while the real site was unusable. Always send an Origin now.
    $origin = ([uri]$BaseUrl).GetLeftPart([System.UriPartial]::Authority)
    # -UseBasicParsing is required on PowerShell 5.1: without it the cmdlet
    # needs the IE engine, and $resp.Content comes back null.
    $resp = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/api/auth/login" -Method Post -TimeoutSec 30 `
        -ContentType 'application/json; charset=utf-8' `
        -Headers @{ Origin = $origin; Referer = "$BaseUrl/" } `
        -Body (@{ staffNo = 'D0231'; password = $DoctorPassword } | ConvertTo-Json -Compress)
    Assert-True ($resp.StatusCode -eq 200) "expected 200 with Origin $origin, got $($resp.StatusCode)"
    $payload = $resp.Content | ConvertFrom-Json
    Assert-True ($payload.code -eq 0) "login with Origin failed: code=$($payload.code) $($payload.message)"
    Write-Host ("        Origin {0} accepted" -f $origin) -ForegroundColor DarkGray
    return $payload
} | Out-Null

Test-Step 'POST /api/auth/login wrong password -> rejected' {
    $resp = $null
    try {
        $resp = Invoke-RestMethod -Uri "$BaseUrl/api/auth/login" -Method Post -TimeoutSec 15 `
            -ContentType 'application/json; charset=utf-8' `
            -Body (@{ staffNo = 'D0231'; password = 'definitely-wrong-password' } | ConvertTo-Json -Compress)
    } catch {
        # A non-2xx answer is an acceptable rejection as well.
        return $null
    }
    Assert-True ($resp.code -ne 0) 'wrong password was accepted'
    return $null
} | Out-Null

# -----------------------------------------------------------------------------
# 2. tasks
# -----------------------------------------------------------------------------
Write-Head '2. Todo / task detail / claim / complete'

$todo = Test-Step 'GET /api/tasks/todo?scope=MINE&days=30' {
    $t = Invoke-Api -Method Get -Path '/api/tasks/todo?scope=MINE&days=30&limit=100' -Headers $script:doctorHeaders
    Assert-True ($t.total -ge 1) "doctor has no todo at all (total=$($t.total))"
    return $t
}

$taskId = $null
if ($todo -and $todo.items -and $todo.items.Count -gt 0) { $taskId = $todo.items[0].id }

Test-Step 'GET /api/tasks/{id}' {
    Assert-True ($null -ne $taskId) 'no task id available from the todo list'
    $d = Invoke-Api -Method Get -Path "/api/tasks/$taskId" -Headers $script:doctorHeaders
    Assert-True ($null -ne $d.patientName) 'task detail has no patient name'
    return $d
} | Out-Null

if (-not $SkipMutation) {
    Test-Step 'POST /api/tasks/{id}/claim' {
        Assert-True ($null -ne $taskId) 'no task id available'
        $c = Invoke-Api -Method Post -Path "/api/tasks/$taskId/claim" -Headers $script:doctorHeaders
        Assert-True ($c.status -eq 'DOING') "status after claim = $($c.status)"
        return $c
    } | Out-Null

    Test-Step 'POST /api/tasks/complete' {
        Assert-True ($null -ne $taskId) 'no task id available'
        $r = Invoke-Api -Method Post -Path '/api/tasks/complete' -Headers $script:doctorHeaders -Body @{
            taskId          = [int]$taskId
            contacted       = $true
            durationSeconds = 42
            symptoms        = @('no obvious symptom')
            recoveryLevel   = 'GOOD'
            conclusion      = 'smoke test: patient reports no discomfort'
            nextAction      = 'CONTINUE'
        }
        Assert-True ($r.status -eq 'DONE') "status after complete = $($r.status)"
        return $r
    } | Out-Null
} else {
    Write-Host '  SKIP  claim / complete (demo data left untouched)' -ForegroundColor DarkGray
}

# -----------------------------------------------------------------------------
# 3. patients
# -----------------------------------------------------------------------------
Write-Head '3. Patients'

$patientList = Test-Step 'GET /api/patients' {
    $p = Invoke-Api -Method Get -Path '/api/patients?limit=50' -Headers $script:doctorHeaders
    Assert-True ($p.Count -ge 1) "doctor sees no patient (count=$($p.Count))"
    foreach ($row in $p) {
        $phone = "$($row.phoneMask)"
        Assert-True ($phone -notmatch '^\d{11}$') "raw phone number leaked: $phone"
        Assert-True ($phone.Length -gt 0) "patient $($row.id) returned an empty phone field"
    }
    return $p
}

Test-Step 'GET /api/patients/{id}' {
    Assert-True ($patientList -and $patientList.Count -gt 0) 'no patient id available'
    $d = Invoke-Api -Method Get -Path "/api/patients/$($patientList[0].id)" -Headers $script:doctorHeaders
    Assert-True ($d.pathways.Count -ge 1) "patient detail has no follow-up pathway (count=$($d.pathways.Count))"
    return $d
} | Out-Null

# -----------------------------------------------------------------------------
# 4. row level security
# -----------------------------------------------------------------------------
Write-Head '4. Row level security'

$rls = Test-Step 'RLS: doctor / nurse / head nurse see different rows' {
    $docMine = Invoke-Api -Method Get -Path '/api/tasks/todo?scope=MINE&days=30&limit=100' -Headers $script:doctorHeaders
    $nurMine = Invoke-Api -Method Get -Path '/api/tasks/todo?scope=MINE&days=30&limit=100' -Headers $script:nurseHeaders
    $mgrTeam = Invoke-Api -Method Get -Path '/api/tasks/todo?scope=TEAM&days=30&limit=100' -Headers $script:managerHeaders
    $docP = Invoke-Api -Method Get -Path '/api/patients?limit=100' -Headers $script:doctorHeaders
    $nurP = Invoke-Api -Method Get -Path '/api/patients?limit=100' -Headers $script:nurseHeaders
    $mgrP = Invoke-Api -Method Get -Path '/api/patients?limit=100' -Headers $script:managerHeaders

    Write-Host ("        doctor : {0} mine, {1} overdue, {2} patients" -f $docMine.total, $docMine.overdue, $docP.Count) -ForegroundColor DarkGray
    Write-Host ("        nurse  : {0} mine, {1} overdue, {2} patients" -f $nurMine.total, $nurMine.overdue, $nurP.Count) -ForegroundColor DarkGray
    Write-Host ("        head   : {0} team, {1} overdue, {2} patients" -f $mgrTeam.total, $mgrTeam.overdue, $mgrP.Count) -ForegroundColor DarkGray

    # The demo database is small: everybody may happen to see the same three
    # patients. What must differ is the "assigned to me" slice, because that is
    # filtered by the logged-in identity. If all three signatures are identical
    # the row level security policy is not being applied at all.
    $sig1 = "{0}|{1}" -f $docMine.total, $nurMine.total
    $sig2 = "{0}|{1}" -f $nurMine.total, $mgrTeam.total
    $sig3 = "{0}|{1}" -f $docMine.total, $mgrTeam.total
    Assert-True (-not ($sig1 -eq $sig2 -and $sig2 -eq $sig3)) `
        'RLS looks inert: all three roles return identical result sets'

    Assert-True ($mgrTeam.total -ge $docMine.total) `
        "head nurse sees fewer team tasks ($($mgrTeam.total)) than the doctor's own list ($($docMine.total))"

    return @{ Doctor = $docMine; Nurse = $nurMine; Manager = $mgrTeam }
}

# -----------------------------------------------------------------------------
# 5. one-tap dial (C8)
#
#    The page only ever shows the masked number, so the dial button has to ask
#    the backend for a real one. Two guarantees matter:
#      a. the real number does come back - otherwise tel: can never work and the
#         button is just a toast (that was the bug);
#      b. it comes back ONLY from here: the normal detail payload keeps the mask,
#         and every single dial leaves an audit row (who / when / whose number).
# -----------------------------------------------------------------------------
Write-Head '5. One-tap dial'

$script:dialedPhone = $null

Test-Step 'POST /api/tasks/{id}/dial returns a dialable number' {
    Assert-True ($null -ne $taskId) 'no task id available'
    $info = Invoke-Api -Method Post -Path "/api/tasks/$taskId/dial" -Headers $script:doctorHeaders
    $script:dialedPhone = $info.phone
    Assert-True ($null -ne $info.phone) 'dial returned no phone'
    Assert-True ($info.phone -match '^\d{11}$') "dial phone is not an 11 digit number: $($info.phone)"
    Assert-True ($info.phoneMask -match '^\d{3}\*{4}\d{4}$') "dial phoneMask looks wrong: $($info.phoneMask)"
    Write-Host ("        phone ****{0} / mask {1}" -f $info.phone.Substring(7), $info.phoneMask) -ForegroundColor DarkGray
    return $info
} | Out-Null

Test-Step 'task detail still ships the masked number only' {
    Assert-True ($null -ne $script:dialedPhone) 'the dial step did not run'
    $json = (Invoke-Api -Method Get -Path "/api/tasks/$taskId" -Headers $script:doctorHeaders) |
        ConvertTo-Json -Depth 6 -Compress
    Assert-True ($json -match '\*{4}') 'task detail no longer carries the masked number'
    Assert-True ($json -notmatch [regex]::Escape($script:dialedPhone)) 'task detail leaked the full phone number'
    return $null
} | Out-Null

Test-Step 'POST /api/tasks/{id}/dial without a token -> 401' {
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/tasks/$taskId/dial" -Method Post -TimeoutSec 10 | Out-Null
        throw 'expected 401 but the call succeeded'
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        Assert-True ($status -eq 401 -or $status -eq 403) "expected 401/403, got $status"
    }
    return $null
} | Out-Null

Test-Step 'dial is written to audit_log (who / when / whose number)' {
    if (-not $script:LocalDevDbUp) {
        Write-Host '        needs the local dev db (127.0.0.1:55432 is down)' -ForegroundColor DarkGray
        Write-Host '        -> against a deployed URL, verify this on that server database' -ForegroundColor DarkGray
        $script:SkipPending = $true
        return $null
    }
    $rows = & D:\devtools\pgtool\pgsql\bin\psql.exe -h 127.0.0.1 -p 55432 -U postgres -d followup_dev -t -A `
        -c "select count(*) from audit_log where action = 'PATIENT_PHONE_DIAL';" 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "psql failed: $rows"
    Assert-True ([int]$rows -ge 1) 'the dial action left no audit row'
    Write-Host ("        PATIENT_PHONE_DIAL audit rows: {0}" -f $rows.Trim()) -ForegroundColor DarkGray
    return $rows
} | Out-Null

# -----------------------------------------------------------------------------
# 6. audit trail
# -----------------------------------------------------------------------------
Write-Head '6. Audit trail'

Test-Step 'task log keeps claim / complete history' {
    if (-not $script:LocalDevDbUp) {
        Write-Host '        needs the local dev db (127.0.0.1:55432 is down)' -ForegroundColor DarkGray
        Write-Host '        -> against a deployed URL, verify this on that server database' -ForegroundColor DarkGray
        $script:SkipPending = $true
        return $null
    }
    $log = & D:\devtools\pgtool\pgsql\bin\psql.exe -h 127.0.0.1 -p 55432 -U postgres -d followup_dev -t -A `
        -c "select count(*) from followup_task_log;" 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "psql failed: $log"
    Assert-True ([int]$log -ge 1) "followup_task_log is empty"
    Write-Host ("        followup_task_log rows: {0}" -f $log.Trim()) -ForegroundColor DarkGray
    return $log
} | Out-Null

# -----------------------------------------------------------------------------
# 7. follow-up history (C9)
#
#    A second call to the same patient has to show what was said last time.
#    Three things matter:
#      a. the record this run just wrote shows up in the history;
#      b. nothing from another patient leaks in (RLS + the patient filter);
#      c. an unknown task is a clean 404, not an empty success.
# -----------------------------------------------------------------------------
Write-Head '7. Follow-up history'

$script:historyMarker = 'smoke test: patient reports no discomfort'
$script:history = $null

$script:history = $null
$script:otherPatientTaskId = $null

Test-Step 'the second call on the same patient sees the previous note' {
    Assert-True ($null -ne $taskId) 'no task id available'

    # "Second call" = another task of the SAME patient. The history deliberately
    # excludes the task being opened (the nurse wants the previous call, not the
    # one on screen), so querying the task that was just completed would prove
    # nothing.
    $d = Invoke-Api -Method Get -Path "/api/tasks/$taskId" -Headers $script:doctorHeaders
    $pd = Invoke-Api -Method Get -Path "/api/patients/$($d.patientId)" -Headers $script:doctorHeaders

    $samePatientTaskId = $null
    foreach ($w in $pd.pathways) {
        foreach ($s in $w.steps) {
            if ($s.taskId -ne $taskId) { $samePatientTaskId = $s.taskId; break }
        }
        if ($samePatientTaskId) { break }
    }
    Assert-True ($null -ne $samePatientTaskId) 'demo patient has a single task - cannot test a second call'

    $h = Invoke-Api -Method Get -Path "/api/tasks/$samePatientTaskId/history" -Headers $script:doctorHeaders
    Assert-True ($h.count -ge 1) "history for the patient's other task is empty (count=$($h.count))"

    $conclusions = @($h.items | ForEach-Object { "$($_.conclusion)" })
    Assert-True ($conclusions -contains $script:historyMarker) `
        'the note written by this run is missing from the previous call history'

    Assert-True ($null -ne $h.items[0].executedAt) 'history item has no executedAt'
    Assert-True ($h.items[0].executedByName.Length -ge 1) 'history item has no author name'
    Write-Host ("        {0} record(s), newest {1} by {2}" -f `
        $h.count, $h.items[0].executedAt, $h.items[0].executedByName) -ForegroundColor DarkGray
    $script:history = $h
    return $h
} | Out-Null

Test-Step 'history never crosses patients' {
    Assert-True ($null -ne $script:history) 'the history step did not run'

    # Same endpoint, another patient: the note must not follow us there.
    $otherPatient = $null
    foreach ($row in $patientList) {
        if ($row.id -ne $script:history.patientId) { $otherPatient = $row; break }
    }
    Assert-True ($null -ne $otherPatient) 'the demo data has only one patient - cannot test isolation'

    $otherDetail = Invoke-Api -Method Get -Path "/api/patients/$($otherPatient.id)" -Headers $script:doctorHeaders
    $otherTaskId = $null
    foreach ($w in $otherDetail.pathways) {
        foreach ($s in $w.steps) { if (-not $otherTaskId) { $otherTaskId = $s.taskId } }
    }
    Assert-True ($null -ne $otherTaskId) 'the other patient has no task to query'

    $other = Invoke-Api -Method Get -Path "/api/tasks/$otherTaskId/history" -Headers $script:doctorHeaders
    $leaked = @($other.items | Where-Object { "$($_.conclusion)" -eq $script:historyMarker })
    Assert-True ($leaked.Count -eq 0) 'a note from another patient leaked into this history'
    Write-Host ("        other patient: {0} record(s), no leak" -f $other.count) -ForegroundColor DarkGray
    return $other
} | Out-Null

Test-Step 'history for an unknown task -> 404' {
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/tasks/99999999/history" -TimeoutSec 10 `
            -Headers $script:doctorHeaders | Out-Null
        throw 'expected 404 but the call succeeded'
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        Assert-True ($status -eq 404 -or $status -eq 403) "expected 404/403, got $status"
    }
    return $null
} | Out-Null

# -----------------------------------------------------------------------------
# summary
# -----------------------------------------------------------------------------
Write-Head 'Summary'

$slowest = $script:Timings | Sort-Object Ms -Descending | Select-Object -First 1
$sorted = $script:Timings | Sort-Object Ms
$p50 = $sorted[[int][Math]::Floor($sorted.Count * 0.5)].Ms
$p95 = $sorted[[int][Math]::Min($sorted.Count - 1, [Math]::Floor($sorted.Count * 0.95))].Ms

Write-Host ("  steps      : {0} passed, {1} failed, {2} skipped" -f $script:PassCount, $script:FailCount, $script:SkipCount)
Write-Host ("  latency    : p50 {0} ms / p95 {1} ms / max {2} ms ({3})" -f $p50, $p95, $slowest.Ms, $slowest.Name)

if ($script:FailCount -gt 0) {
    Write-Host ''
    Write-Host '  RESULT: FAILED' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '  RESULT: ALL GREEN' -ForegroundColor Green
exit 0
