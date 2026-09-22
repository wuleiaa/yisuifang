# =============================================================================
#  Patient portal smoke test (/api/portal).
#
#  Covers the things that are easy to get wrong in a patient-facing API:
#    * login by phone + SMS code (dev mode returns the code)
#    * a patient can only ever see his / her own data
#    * unpublished pathology reports must NOT be visible
#    * a patient token must not work on staff or admin endpoints
#
#  IMPORTANT: keep this file ASCII-only.
# =============================================================================

param(
    [string]$BaseUrl = 'http://127.0.0.1:8080'
)

$ErrorActionPreference = 'Stop'
$script:Pass = 0
$script:Fail = 0

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
        $script:Pass++
        Write-Host ("  PASS  {0,-48} {1,5} ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Green
        return $v
    } catch {
        $sw.Stop()
        $script:Fail++
        Write-Host ("  FAIL  {0,-48} {1,5} ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Red
        Write-Host ("        {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Portal {
    param([string]$Method, [string]$Path, [hashtable]$Headers = @{}, $Body = $null)
    $p = @{ Uri = "$BaseUrl$Path"; Method = $Method; Headers = $Headers; TimeoutSec = 30 }
    if ($null -ne $Body) {
        $p.Body = ($Body | ConvertTo-Json -Depth 6 -Compress)
        $p.ContentType = 'application/json; charset=utf-8'
    }
    $r = Invoke-RestMethod @p
    if ($r.code -ne 0) { throw "api error code=$($r.code) message=$($r.message)" }
    return $r.data
}

function Connect-Patient([string]$Phone) {
    $code = Invoke-Portal -Method Post -Path '/api/portal/auth/code' -Body @{ phone = $Phone }
    Assert-True ($null -ne $code.devCode) 'dev mode should return the verification code'
    $login = Invoke-Portal -Method Post -Path '/api/portal/auth/login' `
        -Body @{ phone = $Phone; code = $code.devCode }
    Assert-True ($login.token.Length -gt 20) 'login returned no token'
    return @{ Headers = @{ Authorization = "Bearer $($login.token)" }; Profile = $login.profile }
}

Write-Head "Patient portal smoke test  ($BaseUrl)"

$chen = $null

Test-Step 'POST /api/portal/auth/code (known patient)' {
    $c = Invoke-Portal -Method Post -Path '/api/portal/auth/code' -Body @{ phone = '13800000003' }
    Assert-True ($c.phoneMask -match '\*') "phone should be masked, got $($c.phoneMask)"
    return $c
} | Out-Null

Test-Step 'POST /api/portal/auth/code (unknown phone, no info leak)' {
    $c = Invoke-Portal -Method Post -Path '/api/portal/auth/code' -Body @{ phone = '13900000000' }
    Assert-True ($null -ne $c.expireSeconds) 'response shape must be identical for unknown phones'
    return $c
} | Out-Null

Test-Step 'POST /api/portal/auth/login (wrong code rejected)' {
    $null = Invoke-Portal -Method Post -Path '/api/portal/auth/code' -Body @{ phone = '13800000003' }
    $rejected = $false
    try {
        Invoke-Portal -Method Post -Path '/api/portal/auth/login' `
            -Body @{ phone = '13800000003'; code = '000000' } | Out-Null
    } catch {
        $rejected = $true
    }
    Assert-True $rejected 'a wrong verification code was accepted'
    return $null
} | Out-Null

Test-Step 'POST /api/portal/auth/login (patient 13800000003)' {
    $script:chen = Connect-Patient '13800000003'
    Assert-True ($script:chen.Profile.name.Length -ge 1) 'profile name missing'
    return $script:chen
} | Out-Null

Test-Step 'GET /api/portal/me' {
    $me = Invoke-Portal -Method Get -Path '/api/portal/me' -Headers $script:chen.Headers
    Assert-True ($me.phoneMask -notmatch '^\d{11}$') "raw phone leaked: $($me.phoneMask)"
    return $me
} | Out-Null

Test-Step 'GET /api/portal/timeline' {
    $t = Invoke-Portal -Method Get -Path '/api/portal/timeline' -Headers $script:chen.Headers
    Assert-True ($t.items.Count -ge 1) "timeline is empty (count=$($t.items.Count))"
    Write-Host ("        {0} follow-up items, {1} pending, {2} overdue" -f $t.items.Count, $t.pendingCount, $t.overdueCount) -ForegroundColor DarkGray
    return $t
} | Out-Null

Test-Step 'GET /api/portal/reports (published report visible)' {
    # NOTE: wrap in @() on purpose.
    # Windows PowerShell 5.1 unwraps a single-element JSON array into a bare
    # object, so .Count would be $null and the check below would report a false
    # failure even though the API returned the report correctly.
    $r = @(Invoke-Portal -Method Get -Path '/api/portal/reports' -Headers $script:chen.Headers)
    Assert-True ($r.Count -ge 1) 'the published pathology report is not visible'
    Assert-True ($null -ne $r[0].plainText) 'doctor interpretation is missing'
    return $r
} | Out-Null

Test-Step 'GET /api/portal/reports (unpublished report hidden)' {
    $zhang = Connect-Patient '13800000001'
    $r = @(Invoke-Portal -Method Get -Path '/api/portal/reports' -Headers $zhang.Headers)
    Assert-True ($r.Count -eq 0) "patient can see unpublished reports (count=$($r.Count)) - publish gate broken"
    return $r
} | Out-Null

Test-Step 'POST /api/portal/tasks/{id}/questionnaire' {
    $t = Invoke-Portal -Method Get -Path '/api/portal/timeline' -Headers $script:chen.Headers
    $taskId = $t.items[0].taskId
    $res = Invoke-Portal -Method Post -Path "/api/portal/tasks/$taskId/questionnaire" `
        -Headers $script:chen.Headers `
        -Body @{ answers = @{ q1 = 'no pain'; q2 = 'normal diet'; q3 = 'on time' } }
    Assert-True ($res.recorded -eq $true) 'questionnaire was not recorded'
    return $res
} | Out-Null

Test-Step 'GET /api/portal/questionnaire (questions come from DB)' {
    $q = Invoke-Portal -Method Get -Path '/api/portal/questionnaire' -Headers $script:chen.Headers
    Assert-True ($q.questions.Count -ge 3) "expected at least 3 questions, got $($q.questions.Count)"
    $first = $q.questions[0]
    Assert-True ($first.options.Count -ge 2) 'question options were not parsed from jsonb'
    Write-Host ("        {0} questions, first has {1} options" -f $q.questions.Count, $first.options.Count) -ForegroundColor DarkGray
    return $q
} | Out-Null

Test-Step 'patient token must not reach staff endpoints' {
    $blocked = $false
    try {
        Invoke-Portal -Method Get -Path '/api/tasks/todo?scope=MINE&days=7' -Headers $script:chen.Headers | Out-Null
    } catch {
        $blocked = $true
    }
    Assert-True $blocked 'a patient token was accepted on a staff endpoint'
    return $null
} | Out-Null

Test-Step 'patient cannot read another patient task' {
    # Patient A must not be able to read patient B's task by guessing its id
    $zhang = Connect-Patient '13800000001'
    $zt = Invoke-Portal -Method Get -Path '/api/portal/timeline' -Headers $zhang.Headers
    $foreignId = $zt.items[0].taskId
    $leaked = $false
    try {
        Invoke-Portal -Method Get -Path "/api/portal/tasks/$foreignId" -Headers $script:chen.Headers | Out-Null
        $leaked = $true
    } catch {
        $leaked = $false
    }
    Assert-True (-not $leaked) 'a patient was able to read another patient task'
    return $null
} | Out-Null

Write-Head 'Summary'
Write-Host ("  steps : {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) {
    Write-Host ''
    Write-Host '  RESULT: FAILED' -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host '  RESULT: ALL GREEN' -ForegroundColor Green
exit 0
