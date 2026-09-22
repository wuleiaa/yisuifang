# =============================================================================
#  Stop the dev backend.
#
#  Kills whatever is listening on the backend port (default 8080). mvn
#  spring-boot:run forks a java process, so killing the console window alone
#  leaves the port occupied and the next start fails with "Port 8080 was
#  already in use".
#
#  IMPORTANT: keep this file ASCII-only.
# =============================================================================

param(
    [int]$Port = 8080
)

$conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if (-not $conn) {
    Write-Host "Nothing is listening on port $Port." -ForegroundColor DarkGray
    exit 0
}

foreach ($c in $conn) {
    $procId = $c.OwningProcess
    $name = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
    Write-Host ("Stopping PID {0} ({1}) on port {2} ..." -f $procId, $name, $Port) -ForegroundColor Yellow
    Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 2

$still = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($still) {
    Write-Host "Port $Port is STILL in use. Close it manually before restarting." -ForegroundColor Red
    exit 1
}

Write-Host "Port $Port is free." -ForegroundColor Green
