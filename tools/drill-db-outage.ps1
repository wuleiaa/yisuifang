# =============================================================================
#  Outage drill: what happens when the database goes away.
#
#  Scenario: the database restarts for maintenance, crashes, or the network
#  blips. Two things must hold:
#    1. the backend fails fast with a clean error instead of hanging and
#       eventually exhausting its request threads
#    2. once the database is back, the backend recovers on its own
#       (no manual restart of the application)
#
#  This script really stops and starts PostgreSQL. It is repeatable and does
#  not lose data.
#
#  IMPORTANT: keep this file ASCII-only. PowerShell 5.1 reads BOM-less .ps1 as
#  GBK on Chinese Windows; Chinese text here causes parse errors.
# =============================================================================

param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [int]$RecoverWaitSeconds = 20
)

. "$PSScriptRoot\dev-env.ps1"

function Write-Step([string]$t) {
    Write-Host ''
    Write-Host $t -ForegroundColor Cyan
}

$pgCtl = Join-Path $script:PgHome 'bin\pg_ctl.exe'
$pgLog = Join-Path $script:DevToolRoot 'pgtool\pg.log'
$pgOpts = "-p $($script:PgPort) -c listen_addresses=127.0.0.1 -c shared_buffers=64MB -c max_connections=30 -c work_mem=4MB"

Write-Host 'Database outage drill' -ForegroundColor White

# --- 0. get a working token ----------------------------------------------
Write-Step '0) Login and keep a token'
$login = Invoke-RestMethod -Uri "$BaseUrl/api/auth/login" -Method Post `
    -ContentType 'application/json; charset=utf-8' `
    -Body '{"staffNo":"D0231","password":"Followup@2026"}' -TimeoutSec 15
if ($login.code -ne 0) {
    Write-Host '   login failed, drill aborted' -ForegroundColor Red
    exit 1
}
$headers = @{ Authorization = "Bearer $($login.data.token)" }
Write-Host '   ok' -ForegroundColor Green

# --- 1. stop the database -------------------------------------------------
Write-Step '1) Stop PostgreSQL'
& $pgCtl -D $script:PgData stop -m fast 2>&1 | Select-Object -Last 1
Start-Sleep -Seconds 3

# --- 2. call an endpoint while the database is down ----------------------
Write-Step '2) Call an API while the database is down (expect: fast, clean error)'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $r = Invoke-WebRequest -Uri "$BaseUrl/api/tasks/todo?scope=MINE&days=7" -Headers $headers `
        -UseBasicParsing -TimeoutSec 30
    Write-Host ("   [UNEXPECTED] request succeeded, HTTP {0}" -f $r.StatusCode) -ForegroundColor Red
} catch {
    $status = $null
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    $body = ''
    try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $body = $reader.ReadToEnd()
    } catch { }
    Write-Host ("   HTTP {0}  took {1} ms" -f $status, $sw.ElapsedMilliseconds)
    if ($body) { Write-Host ("   body: {0}" -f $body) }
    if ($sw.ElapsedMilliseconds -lt 15000) {
        Write-Host '   [PASS] failed fast, request threads were not blocked' -ForegroundColor Green
    } else {
        Write-Host '   [WARN] slow response, threads may have been exhausted' -ForegroundColor Yellow
    }
}
$sw.Stop()

# --- 3. bring the database back ------------------------------------------
Write-Step '3) Restart PostgreSQL'
# NOTE: do NOT pipe this through anything.
# pg_ctl start leaves the server running as a child process, so its stdout
# never closes and a pipeline would hang forever (hit this the hard way).
& $pgCtl -D $script:PgData -l $pgLog -o $pgOpts start
Start-Sleep -Seconds 5

# --- 4. verify self healing ----------------------------------------------
Write-Step '4) Call the API again (expect: recovers without restarting the app)'
$deadline = (Get-Date).AddSeconds($RecoverWaitSeconds)
$recovered = $false
while ((Get-Date) -lt $deadline -and -not $recovered) {
    try {
        $r2 = Invoke-RestMethod -Uri "$BaseUrl/api/tasks/todo?scope=MINE&days=7" -Headers $headers -TimeoutSec 15
        if ($r2.code -eq 0) {
            Write-Host ("   [PASS] recovered automatically, todo count = {0}" -f $r2.data.total) -ForegroundColor Green
            $recovered = $true
        }
    } catch {
        Start-Sleep -Seconds 2
    }
}
if (-not $recovered) {
    Write-Host '   [FAIL] database is back but the backend did not recover' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Drill finished.' -ForegroundColor White
