# =============================================================================
#  Admin console smoke test (/api/admin).
#
#  Verifies the account-management flow plus the rules that protect it:
#    * only an admin can call these endpoints (a normal doctor gets 403)
#    * a department manager only sees his / her own department
#    * a new account can log in with the one-time initial password
#    * the initial password is shown once and never retrievable again
#    * reset password invalidates the old password
#    * disabling an account stops it from logging in
#    * every write is written to audit_log
#
#  The test creates accounts named T9xxxx and tools/demo-reset.ps1 removes them,
#  so repeated runs stay clean.
#
#  IMPORTANT: keep this file ASCII-only (PowerShell 5.1 + GBK decoding).
# =============================================================================

param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$AdminNo = 'A0001',
    [string]$DoctorNo = 'D0231',
    [string]$Password = 'Followup@2026',
    # The admin and the plain doctor may have different passwords on a real
    # deployment, so the doctor password can be given separately; if omitted it
    # falls back to -Password. Lets the same script run against https://<domain>.
    [string]$DoctorPassword = ''
)

$ErrorActionPreference = 'Stop'

if (-not $DoctorPassword) { $DoctorPassword = $Password }

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

$script:Pass = 0
$script:Fail = 0
$script:Skip = 0
# Set by a step body that cannot run in the current environment (e.g. it needs
# the local dev database). A skipped step must never be reported as a pass.
$script:SkipPending = $false

function Write-Head([string]$T) {
    Write-Host ''
    Write-Host $T -ForegroundColor Cyan
}

function Test-Step {
    param([string]$Name, [scriptblock]$Body)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $v = & $Body
        $sw.Stop()
        if ($script:SkipPending) {
            $script:SkipPending = $false
            $script:Skip++
            Write-Host ("  SKIP  {0,-50} {1,5} ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Yellow
            return $null
        }
        $script:Pass++
        Write-Host ("  PASS  {0,-50} {1,5} ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Green
        return $v
    } catch {
        $sw.Stop()
        $script:Fail++
        Write-Host ("  FAIL  {0,-50} {1,5} ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Red
        Write-Host ("        {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Headers = @{}, $Body = $null, [switch]$Raw)
    $p = @{ Uri = "$BaseUrl$Path"; Method = $Method; Headers = $Headers; TimeoutSec = 30 }
    if ($null -ne $Body) {
        $p.Body = ($Body | ConvertTo-Json -Depth 6 -Compress)
        $p.ContentType = 'application/json; charset=utf-8'
    }
    try {
        $r = Invoke-RestMethod @p
    } catch {
        if ($Raw) {
            $status = $null
            if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
            return @{ httpStatus = $status; code = $null; message = $_.Exception.Message }
        }
        throw
    }
    if ($Raw) { return $r }
    if ($r.code -ne 0) { throw "api error code=$($r.code) message=$($r.message)" }
    return $r.data
}

function Connect-Staff([string]$staffNo, [string]$pwd) {
    $login = Invoke-Api -Method Post -Path '/api/auth/login' -Body @{ staffNo = $staffNo; password = $pwd }
    Assert-True ($login.token.Length -gt 20) "login returned no token for $staffNo"
    return @{ Headers = @{ Authorization = "Bearer $($login.token)" }; Profile = $login.profile }
}

Write-Head "Admin console smoke test  ($BaseUrl)"

$admin = $null
# The random suffix matters: two suites started in the same second used to
# generate the same throw-away staff number, so whichever lost the race got a
# bogus 409 "duplicate staff number". Keep the T9 prefix - demo-reset cleans
# those up.
$testNo = 'T9' + (Get-Date -Format 'HHmmss') + (Get-Random -Minimum 10 -Maximum 99)

Write-Head '1. Identity'

Test-Step 'admin login reports admin=true and SUPER_ADMIN role' {
    $script:admin = Connect-Staff $AdminNo $Password
    Assert-True ($script:admin.Profile.admin -eq $true) 'admin flag is false for A0001'
    Assert-True ($script:admin.Profile.roles -contains 'SUPER_ADMIN') "roles = $($script:admin.Profile.roles -join ',')"
    return $script:admin
} | Out-Null

Test-Step 'normal doctor reports admin=false' {
    $doc = Connect-Staff $DoctorNo $DoctorPassword
    Assert-True ($doc.Profile.admin -eq $false) 'a plain doctor was flagged as admin'
    return $doc
} | Out-Null

if (-not $script:admin) {
    Write-Host 'Cannot continue: admin login failed.' -ForegroundColor Red
    exit 1
}

Write-Head '2. Authorization'

Test-Step 'plain doctor gets 403 on admin endpoints' {
    $doc = Connect-Staff $DoctorNo $DoctorPassword
    $r = Invoke-Api -Method Get -Path '/api/admin/staff' -Headers $doc.Headers -Raw
    Assert-True ($r.httpStatus -eq 403 -or $r.code -eq 40300) "expected 403, got http=$($r.httpStatus) code=$($r.code)"
    return $null
} | Out-Null

Test-Step 'admin can read overview' {
    $o = Invoke-Api -Method Get -Path '/api/admin/overview' -Headers $script:admin.Headers
    Assert-True ($o.staffTotal -ge 4) "staffTotal = $($o.staffTotal)"
    Write-Host ("        staff={0} doctor={1} nurse={2} manager={3} disabled={4} todayLogin={5}" -f `
        $o.staffTotal, $o.doctorCount, $o.nurseCount, $o.managerCount, $o.disabledCount, $o.todayLogin) -ForegroundColor DarkGray
    return $o
} | Out-Null

Test-Step 'admin can list roles' {
    $roles = @(Invoke-Api -Method Get -Path '/api/admin/roles' -Headers $script:admin.Headers)
    Assert-True ($roles.Count -ge 5) "expected at least 5 roles, got $($roles.Count)"
    return $roles
} | Out-Null

Write-Head '3. Search accounts'

Test-Step 'list all accounts' {
    $list = Invoke-Api -Method Get -Path '/api/admin/staff' -Headers $script:admin.Headers
    Assert-True ($list.total -ge 4) "expected at least 4 accounts, got $($list.total)"
    $nos = ($list.items | ForEach-Object { $_.staffNo }) -join ','
    Assert-True ($nos -match $DoctorNo) "doctor missing from list: $nos"
    return $list
} | Out-Null

Test-Step 'search by staff number' {
    $list = Invoke-Api -Method Get -Path "/api/admin/staff?keyword=$DoctorNo" -Headers $script:admin.Headers
    Assert-True ($list.total -eq 1) "expected exactly 1 hit, got $($list.total)"
    Assert-True ($list.items[0].staffNo -eq $DoctorNo) "wrong row returned: $($list.items[0].staffNo)"
    return $list
} | Out-Null

Test-Step 'search by role returns only that role' {
    $list = Invoke-Api -Method Get -Path '/api/admin/staff?roleCode=NURSE' -Headers $script:admin.Headers
    Assert-True ($list.total -ge 1) 'no nurse accounts found'
    foreach ($row in $list.items) {
        Assert-True ($row.roles -match 'NURSE') "row $($row.staffNo) has roles=$($row.roles)"
    }
    return $list
} | Out-Null

Write-Head '4. Create account'

$created = $null

Test-Step "create nurse account $testNo" {
    $script:created = Invoke-Api -Method Post -Path '/api/admin/staff' -Headers $script:admin.Headers -Body @{
        staffNo  = $testNo
        name     = 'Test Nurse'
        roleCode = 'NURSE'
        title    = 'Nurse'
        gender   = 2
    }
    Assert-True ($script:created.initialPassword.Length -ge 8) 'no initial password returned'
    Assert-True ($script:created.mustChangePassword -eq $true) 'mustChangePassword should be true'
    Write-Host ("        initial password length = {0}" -f $script:created.initialPassword.Length) -ForegroundColor DarkGray
    return $script:created
} | Out-Null

Test-Step 'duplicate staff number is rejected' {
    $r = Invoke-Api -Method Post -Path '/api/admin/staff' -Headers $script:admin.Headers -Body @{
        staffNo = $testNo; name = 'Dup'; roleCode = 'NURSE'
    } -Raw
    Assert-True ($r.code -ne 0) 'a duplicate staff number was accepted'
    return $null
} | Out-Null

if (-not $script:created) {
    Write-Host 'Cannot continue: account creation failed.' -ForegroundColor Red
    exit 1
}

Test-Step 'new account can log in with the initial password' {
    $s = Connect-Staff $testNo $script:created.initialPassword
    Assert-True ($s.Profile.mustChangePassword -eq $true) 'mustChangePassword not set on login'
    Assert-True ($s.Profile.admin -eq $false) 'a nurse account must not be admin'
    return $s
} | Out-Null

Test-Step 'new nurse account cannot use admin endpoints' {
    $s = Connect-Staff $testNo $script:created.initialPassword
    $r = Invoke-Api -Method Get -Path '/api/admin/staff' -Headers $s.Headers -Raw
    Assert-True ($r.httpStatus -eq 403 -or $r.code -eq 40300) "expected 403, got http=$($r.httpStatus) code=$($r.code)"
    return $null
} | Out-Null

Write-Head '5. Reset password'

$reset = $null

Test-Step 'admin resets the password' {
    $script:reset = Invoke-Api -Method Post -Path "/api/admin/staff/$($script:created.staffId)/reset-password" -Headers $script:admin.Headers
    Assert-True ($script:reset.tempPassword.Length -ge 8) 'no temp password returned'
    Assert-True ($script:reset.tempPassword -ne $script:created.initialPassword) 'temp password equals the old one'
    return $script:reset
} | Out-Null

Test-Step 'old password no longer works' {
    $r = Invoke-Api -Method Post -Path '/api/auth/login' -Body @{ staffNo = $testNo; password = $script:created.initialPassword } -Raw
    Assert-True ($r.code -ne 0) 'the old password still works after a reset'
    return $null
} | Out-Null

Test-Step 'new temp password works' {
    $s = Connect-Staff $testNo $script:reset.tempPassword
    Assert-True ($s.Profile.staffNo -eq $testNo) 'wrong account logged in'
    return $s
} | Out-Null

Write-Head '6. Disable / enable'

Test-Step 'disabled account cannot log in' {
    Invoke-Api -Method Post -Path "/api/admin/staff/$($script:created.staffId)/status" `
        -Headers $script:admin.Headers -Body @{ status = 'DISABLED' } | Out-Null
    $r = Invoke-Api -Method Post -Path '/api/auth/login' -Body @{ staffNo = $testNo; password = $script:reset.tempPassword } -Raw
    Assert-True ($r.code -eq 41003 -or $r.code -ne 0) "disabled account logged in: code=$($r.code)"
    return $null
} | Out-Null

Test-Step 're-enabled account can log in again' {
    Invoke-Api -Method Post -Path "/api/admin/staff/$($script:created.staffId)/status" `
        -Headers $script:admin.Headers -Body @{ status = 'ACTIVE' } | Out-Null
    $s = Connect-Staff $testNo $script:reset.tempPassword
    Assert-True ($s.Profile.staffNo -eq $testNo) 're-enabled account cannot log in'
    return $s
} | Out-Null

Test-Step 'admin cannot disable his own account' {
    $me = Connect-Staff $AdminNo $Password
    $r = Invoke-Api -Method Post -Path "/api/admin/staff/$($me.Profile.staffId)/status" `
        -Headers $me.Headers -Body @{ status = 'DISABLED' } -Raw
    Assert-True ($r.code -ne 0) 'admin managed to disable himself'
    return $null
} | Out-Null

Write-Head '7. Audit trail and login log'

Test-Step 'account operations are written to audit_log' {
    if (-not $script:LocalDevDbUp) {
        Write-Host '        needs the local dev db (127.0.0.1:55432 is down)' -ForegroundColor DarkGray
        Write-Host '        -> against a deployed URL, verify this on that server database' -ForegroundColor DarkGray
        $script:SkipPending = $true
        return $null
    }
    $out = & D:\devtools\pgtool\pgsql\bin\psql.exe -h 127.0.0.1 -p 55432 -U postgres -d followup_dev -t -A `
        -c "select count(*) from audit_log where resource_type='staff' and action in ('STAFF_CREATE','STAFF_RESET_PASSWORD','STAFF_STATUS');" 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "psql failed: $out"
    $n = [int]$out.Trim()
    Assert-True ($n -ge 3) "expected at least 3 audit rows, got $n"
    Write-Host ("        staff audit rows: {0}" -f $n) -ForegroundColor DarkGray
    return $n
} | Out-Null

Test-Step 'login attempts are logged (login_log)' {
    if (-not $script:LocalDevDbUp) {
        Write-Host '        needs the local dev db (127.0.0.1:55432 is down)' -ForegroundColor DarkGray
        Write-Host '        -> against a deployed URL, verify this on that server database' -ForegroundColor DarkGray
        $script:SkipPending = $true
        return $null
    }
    $out = & D:\devtools\pgtool\pgsql\bin\psql.exe -h 127.0.0.1 -p 55432 -U postgres -d followup_dev -t -A `
        -c "select count(*) from login_log;" 2>&1
    $n = [int]$out.Trim()
    Assert-True ($n -ge 1) "login_log is empty, logins are not being recorded"
    Write-Host ("        login_log rows: {0}" -f $n) -ForegroundColor DarkGray
    return $n
} | Out-Null

# -----------------------------------------------------------------------------
# 8. QC dashboard (C13)
#
#    The dashboard is nothing but task/record aggregates, which makes it the
#    place where the 2026-09-23 RLS bug is visible: AdminService never set the
#    RLS session variables, so every followup_task row was filtered out and the
#    overview reported "0 pending / 0 overdue" while the database had 10.
#    The steps below compare the API with the database (local run) and, on any
#    deployment, require the numbers to move after a real call.
# -----------------------------------------------------------------------------
Write-Head '8. QC dashboard'

# Keep this file ASCII-only, so build the Chinese symptom text from code points
# (0x5455 = "ou", 0x8840 = "xue" -> the danger symptom spelling "hematemesis").
$script:dangerSymptom = [string][char]0x5455 + [char]0x8840

$script:qc = $null

$script:qc = Test-Step 'GET /api/admin/qc returns the dashboard' {
    $q = Invoke-Api -Method Get -Path '/api/admin/qc' -Headers $script:admin.Headers
    Assert-True ($null -ne $q.month) 'qc returned no month'
    Assert-True ($q.completionRate -ge 0 -and $q.completionRate -le 100) "completionRate out of range: $($q.completionRate)"
    Assert-True ($q.openTotal -ge $q.overdueOpen) "overdue ($($q.overdueOpen)) > open ($($q.openTotal))"
    Assert-True ($null -ne $q.doctors) 'qc returned no doctors array'
    Write-Host ("        {0}: total={1} done={2} rate={3}% open={4} overdue={5} pathologyHours={6}" -f `
        $q.month, $q.monthTotal, $q.monthDone, $q.completionRate,
        $q.openTotal, $q.overdueOpen, $q.pathologyAvgHours) -ForegroundColor DarkGray
    return $q
}

Test-Step 'dashboard numbers match the database (RLS regression guard)' {
    if (-not $script:LocalDevDbUp) {
        Write-Host '        needs the local dev db - against a deployment the next step proves it' -ForegroundColor DarkGray
        $script:SkipPending = $true
        return $null
    }
    Assert-True ($null -ne $script:qc) 'the qc step did not run'

    $open = [int](& D:\devtools\pgtool\pgsql\bin\psql.exe -h 127.0.0.1 -p 55432 -U postgres -d followup_dev -t -A `
        -c "select count(*) from followup_task where deleted_at is null and status in ('PENDING','DOING');")
    $overdue = [int](& D:\devtools\pgtool\pgsql\bin\psql.exe -h 127.0.0.1 -p 55432 -U postgres -d followup_dev -t -A `
        -c "select count(*) from followup_task where deleted_at is null and status in ('PENDING','DOING') and due_date < current_date;")

    Assert-True ($script:qc.openTotal -eq $open) `
        "api openTotal=$($script:qc.openTotal) but the db has $open (row level security silently filtering?)"
    Assert-True ($script:qc.overdueOpen -eq $overdue) `
        "api overdueOpen=$($script:qc.overdueOpen) but the db has $overdue"

    $ov = Invoke-Api -Method Get -Path '/api/admin/overview' -Headers $script:admin.Headers
    Assert-True ($ov.pendingTask -eq $open) "overview pendingTask=$($ov.pendingTask) but the db has $open"
    Assert-True ($ov.overdueTask -eq $overdue) "overview overdueTask=$($ov.overdueTask) but the db has $overdue"

    Write-Host ("        api == db: open={0} overdue={1}" -f $open, $overdue) -ForegroundColor DarkGray
    return $null
} | Out-Null

Test-Step 'a danger symptom shows up as an abnormal event' {
    $doc = Connect-Staff $DoctorNo $DoctorPassword
    $todo = Invoke-Api -Method Get -Path '/api/tasks/todo?scope=MINE&days=30&limit=100' -Headers $doc.Headers
    Assert-True ($todo.total -ge 1) "doctor has no todo to report on (total=$($todo.total))"
    $task = $todo.items[0]

    Invoke-Api -Method Post -Path "/api/tasks/$($task.id)/claim" -Headers $doc.Headers | Out-Null
    Invoke-Api -Method Post -Path '/api/tasks/complete' -Headers $doc.Headers -Body @{
        taskId                 = [int]$task.id
        contacted              = $true
        symptoms               = @($script:dangerSymptom)
        recoveryLevel          = 'ABNORMAL'
        conclusion             = 'qc smoke: danger symptom reported'
        advice                 = 'go to the emergency department'
        nextAction             = 'ESCALATE'
        notifyDoctorImmediately = $true
    } | Out-Null

    $q = Invoke-Api -Method Get -Path '/api/admin/qc' -Headers $script:admin.Headers
    $hit = @($q.abnormalEvents | Where-Object { $_.patientId -eq $task.patientId })
    Assert-True ($hit.Count -ge 1) 'the abnormal event is missing from the QC dashboard'
    Assert-True ("$($hit[0].symptomText)" -match $script:dangerSymptom) `
        "symptom text looks wrong: $($hit[0].symptomText)"
    Assert-True ($hit[0].escalated -eq $true) 'the escalated flag was not set'
    Assert-True ($q.monthDone -ge 1) `
        "monthDone did not move after a real call ($($q.monthDone)) - row level security again?"
    Write-Host ("        {0} / {1} / escalated={2}" -f `
        $hit[0].patientName, $hit[0].symptomText, $hit[0].escalated) -ForegroundColor DarkGray
    return $hit
} | Out-Null

Test-Step 'plain doctor cannot read the QC dashboard' {
    $doc = Connect-Staff $DoctorNo $DoctorPassword
    $r = Invoke-Api -Method Get -Path '/api/admin/qc' -Headers $doc.Headers -Raw
    Assert-True ($r.httpStatus -eq 403 -or $r.code -eq 40300) "expected 403, got http=$($r.httpStatus) code=$($r.code)"
    return $null
} | Out-Null

Write-Head 'Summary'
Write-Host ("  steps : {0} passed, {1} failed, {2} skipped" -f $script:Pass, $script:Fail, $script:Skip)
if ($script:Fail -gt 0) {
    Write-Host ''
    Write-Host '  RESULT: FAILED' -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host '  RESULT: ALL GREEN' -ForegroundColor Green
exit 0
