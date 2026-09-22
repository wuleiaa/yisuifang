# =============================================================================
#  Security regression checks for the staff / admin API.
#
#  These are the guarantees that silently disappear when auth code is touched:
#    1. an account flagged "must change password" can only reach the
#       change-password endpoints; the rest of the API returns 403 / 41005
#    2. the very same token works normally right after the password is changed
#       (the check reads the database, not a claim baked into the old token)
#    3. a disabled account's existing token stops working immediately
#    4. a FAILED password change is still written to audit_log
#       (it used to be rolled back together with the failed transaction)
#    5. login_log records ip + user_agent
#
#  The test works on a throw-away account it creates through the admin API
#  (staff number T9xxxx, removed by tools/demo-reset.ps1), and it only changes
#  that account's password - never the accounts you log in with.
#
#  Usage:
#    powershell -File .\tools\security-smoke-test.ps1
#    powershell -File .\tools\security-smoke-test.ps1 -BaseUrl https://yisuifang.work `
#        -AdminNo A0001 -Password 'the admin password'
#
#  IMPORTANT: keep this file ASCII-only (PowerShell 5.1 + GBK decoding).
# =============================================================================

param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$AdminNo = 'A0001',
    [string]$Password = 'Followup@2026'
)

$ErrorActionPreference = 'Stop'

# Steps 4 and 5 read the database directly, which only works against the local
# dev database. Against a deployed URL verify them on that server instead.
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
$script:SkipPending = $false

function Write-Head([string]$T) {
    Write-Host ''
    Write-Host $T -ForegroundColor Cyan
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
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
            Write-Host ("  SKIP  {0,-52} {1,5} ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Yellow
            return $null
        }
        $script:Pass++
        Write-Host ("  PASS  {0,-52} {1,5} ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Green
        return $v
    } catch {
        $sw.Stop()
        $script:Fail++
        Write-Host ("  FAIL  {0,-52} {1,5} ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Red
        Write-Host ("        {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

# Invoke-Api returns the raw envelope { code, message, data } plus http status,
# because this suite cares about the exact failure code.
function Invoke-Raw {
    param([string]$Method, [string]$Path, [hashtable]$Headers = @{}, $Body = $null)
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
    try {
        $resp = Invoke-RestMethod @params
        return [pscustomobject]@{ http = 200; code = $resp.code; message = $resp.message; data = $resp.data }
    } catch {
        $status = 0
        $payload = $null
        $text = $null
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        # Windows PowerShell puts the response body in ErrorDetails.Message;
        # reading the response stream directly usually comes back empty because
        # the caller has already consumed it.
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $text = $_.ErrorDetails.Message
        } elseif ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $text = $reader.ReadToEnd()
            } catch { }
        }
        if ($text) {
            try { $payload = $text | ConvertFrom-Json } catch { }
        }
        return [pscustomobject]@{
            http = $status
            code = if ($payload) { $payload.code } else { -1 }
            message = if ($payload) { $payload.message } else { $_.Exception.Message }
            data = $null
        }
    }
}

function Login([string]$staffNo, [string]$pwd) {
    $r = Invoke-Raw -Method Post -Path '/api/auth/login' -Body @{ staffNo = $staffNo; password = $pwd }
    Assert-True ($r.code -eq 0) "login failed for $staffNo : http=$($r.http) code=$($r.code) $($r.message)"
    return @{
        Token    = $r.data.token
        Headers  = @{ Authorization = "Bearer $($r.data.token)" }
        Profile  = $r.data.profile
    }
}

Write-Host ''
Write-Host "Security smoke test  ($BaseUrl)" -ForegroundColor Cyan

$testNo = 'T9' + (Get-Date -Format 'HHmmss')
$admin = $null
$created = $null
$temp = $null

Write-Head '1. Admin session and throw-away account'

Test-Step 'admin can log in and is not stuck in must-change state' {
    $script:admin = Login $AdminNo $Password
    Assert-True ($script:admin.Profile.admin -eq $true) 'admin flag is false'
    Assert-True ($script:admin.Profile.mustChangePassword -eq $false) `
        'the admin account still has must_change_password set - change it in the app first, then re-run'
    return $null
} | Out-Null

if (-not $script:admin) {
    Write-Host ''
    Write-Host 'Cannot continue: admin session not available.' -ForegroundColor Red
    exit 1
}

Test-Step "create nurse account $testNo" {
    $script:created = Invoke-Raw -Method Post -Path '/api/admin/staff' -Headers $script:admin.Headers -Body @{
        staffNo  = $testNo
        name     = 'Security Test'
        roleCode = 'NURSE'
        gender   = 2
        title    = 'Nurse'
    }
    Assert-True ($script:created.code -eq 0) "create failed: $($script:created.message)"
    $script:createdData = $script:created.data
    Assert-True ($script:createdData.initialPassword.Length -ge 8) 'no initial password returned'
    return $script:created
} | Out-Null

if (-not $script:created) {
    Write-Host ''
    Write-Host 'Cannot continue: could not create the test account.' -ForegroundColor Red
    exit 1
}

Write-Head '2. A must-change-password account cannot use the API'

Test-Step 'new account: mustChangePassword flag is set' {
    $script:temp = Login $testNo $script:createdData.initialPassword
    Assert-True ($script:temp.Profile.mustChangePassword -eq $true) 'flag is not set on a fresh account'
    return $null
} | Out-Null

Test-Step 'blocked on a business endpoint (403 / 41005)' {
    $r = Invoke-Raw -Method Get -Path '/api/tasks/todo?scope=MINE&days=30' -Headers $script:temp.Headers
    Assert-True ($r.http -eq 403) "expected http 403, got $($r.http)"
    Assert-True ($r.code -eq 41005) "expected code 41005, got $($r.code)"
    return $r
} | Out-Null

Test-Step 'blocked on the admin endpoints (403 / 41005)' {
    $r = Invoke-Raw -Method Get -Path '/api/admin/staff' -Headers $script:temp.Headers
    Assert-True ($r.http -eq 403 -and $r.code -eq 41005) "got http=$($r.http) code=$($r.code)"
    return $r
} | Out-Null

Test-Step 'still allowed on /api/auth/me' {
    $r = Invoke-Raw -Method Get -Path '/api/auth/me' -Headers $script:temp.Headers
    Assert-True ($r.code -eq 0) "me failed: http=$($r.http) code=$($r.code)"
    return $r
} | Out-Null

Write-Head '3. Changing the password lifts the restriction'

Test-Step 'change own password' {
    $newPwd = 'NewPwd' + (Get-Random -Minimum 100000 -Maximum 999999) + 'x'
    $r = Invoke-Raw -Method Post -Path '/api/auth/change-password' -Headers $script:temp.Headers `
        -Body @{ oldPassword = $script:createdData.initialPassword; newPassword = $newPwd }
    Assert-True ($r.code -eq 0) "change failed: http=$($r.http) code=$($r.code) $($r.message)"
    $script:newPwd = $newPwd
    return $r
} | Out-Null

Test-Step 'same token now reaches a business endpoint' {
    $r = Invoke-Raw -Method Get -Path '/api/tasks/todo?scope=MINE&days=30' -Headers $script:temp.Headers
    Assert-True ($r.code -eq 0) "still blocked after the change: http=$($r.http) code=$($r.code)"
    return $r
} | Out-Null

Test-Step 'old password no longer works' {
    $r = Invoke-Raw -Method Post -Path '/api/auth/login' -Body @{
        staffNo = $testNo; password = $script:createdData.initialPassword
    }
    Assert-True ($r.code -ne 0) 'the initial password still works after the change'
    return $null
} | Out-Null

Test-Step 'wrong old password is rejected and audit_log keeps the FAIL row' {
    $r = Invoke-Raw -Method Post -Path '/api/auth/change-password' -Headers $script:temp.Headers `
        -Body @{ oldPassword = 'definitely-wrong-1'; newPassword = 'Another1234x' }
    Assert-True ($r.code -ne 0) 'a wrong old password was accepted'

    if (-not $script:LocalDevDbUp) {
        Write-Host '        needs the local dev db (127.0.0.1:55432 is down)' -ForegroundColor DarkGray
        Write-Host '        -> against a deployed URL, check audit_log on that server' -ForegroundColor DarkGray
        $script:SkipPending = $true
        return $null
    }
    $n = & D:\devtools\pgtool\pgsql\bin\psql.exe -h 127.0.0.1 -p 55432 -U postgres -d followup_dev -t -A `
        -c "select count(*) from audit_log where action='STAFF_CHANGE_PASSWORD' and result='FAIL';" 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "psql failed: $n"
    Assert-True ([int]$n.Trim() -ge 1) "expected a FAIL row in audit_log, got $($n.Trim())"
    Write-Host ("        STAFF_CHANGE_PASSWORD result=FAIL rows: {0}" -f $n.Trim()) -ForegroundColor DarkGray
    return $null
} | Out-Null

Write-Head '4. Disabling an account kills its existing token'

Test-Step 'disable the test account' {
    $r = Invoke-Raw -Method Post -Path "/api/admin/staff/$($script:createdData.staffId)/status" `
        -Headers $script:admin.Headers -Body @{ status = 'DISABLED' }
    Assert-True ($r.code -eq 0) "disable failed: $($r.message)"
    return $r
} | Out-Null

Test-Step 'the token issued before the disable is rejected (41003)' {
    $r = Invoke-Raw -Method Get -Path '/api/auth/me' -Headers $script:temp.Headers
    Assert-True ($r.http -eq 401) "expected http 401, got $($r.http)"
    Assert-True ($r.code -eq 41003) "expected code 41003, got $($r.code)"
    return $r
} | Out-Null

Test-Step 're-enable the test account' {
    $r = Invoke-Raw -Method Post -Path "/api/admin/staff/$($script:createdData.staffId)/status" `
        -Headers $script:admin.Headers -Body @{ status = 'ACTIVE' }
    Assert-True ($r.code -eq 0) "enable failed: $($r.message)"
    return $r
} | Out-Null

Write-Head '5. Login log records where the login came from'

Test-Step 'login_log has ip and user_agent filled in' {
    if (-not $script:LocalDevDbUp) {
        Write-Host '        needs the local dev db (127.0.0.1:55432 is down)' -ForegroundColor DarkGray
        Write-Host '        -> against a deployed URL, check login_log on that server' -ForegroundColor DarkGray
        $script:SkipPending = $true
        return $null
    }
    $row = & D:\devtools\pgtool\pgsql\bin\psql.exe -h 127.0.0.1 -p 55432 -U postgres -d followup_dev -t -A `
        -c "select count(*) from login_log where ip is not null and user_agent is not null;" 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "psql failed: $row"
    Assert-True ([int]$row.Trim() -ge 1) 'no login_log row has both ip and user_agent'
    Write-Host ("        rows with ip + user_agent: {0}" -f $row.Trim()) -ForegroundColor DarkGray
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
