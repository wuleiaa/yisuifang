# Stop local dev database
. "$PSScriptRoot\dev-env.ps1"

& "$script:PgHome\bin\pg_ctl.exe" -D "$script:PgData" stop

