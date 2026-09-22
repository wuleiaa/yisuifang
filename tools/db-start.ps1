# Start local dev database (portable PostgreSQL, 127.0.0.1:55432 only)
#
# Memory settings are deliberately small for a low-spec machine:
#   shared_buffers 64MB (default 128MB), max_connections 30 (default 100),
#   work_mem 4MB, maintenance_work_mem 64MB, effective_cache_size 256MB.
# Measured footprint is roughly 120-180 MB RSS, which is comfortable.
. "$PSScriptRoot\dev-env.ps1"

if (-not (Test-Path $script:PgHome)) {
    Write-Host "PostgreSQL not found: $script:PgHome" -ForegroundColor Red
    exit 1
}

$status = & "$script:PgHome\bin\pg_ctl.exe" -D "$script:PgData" status 2>&1
if ($status -match 'server is running') {
    Write-Host 'Database is already running.' -ForegroundColor Green
    exit 0
}

$opts = @(
    "-p $script:PgPort",
    '-c listen_addresses=127.0.0.1',
    '-c shared_buffers=64MB',
    '-c max_connections=30',
    '-c work_mem=4MB',
    '-c maintenance_work_mem=64MB',
    '-c effective_cache_size=256MB',
    '-c timezone=Asia/Shanghai'
) -join ' '

$log = Join-Path $script:DevToolRoot 'pgtool\pg.log'

& "$script:PgHome\bin\pg_ctl.exe" -D "$script:PgData" -l $log -o $opts start

Start-Sleep -Seconds 4
& "$script:PgHome\bin\pg_ctl.exe" -D "$script:PgData" status

