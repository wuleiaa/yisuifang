# =============================================================================
#  Dev environment variables (dot-source from other scripts)
#
#  IMPORTANT 1: keep this file ASCII-only.
#    Windows PowerShell 5.1 reads .ps1 as ANSI (GBK on Chinese Windows) when the
#    file has no UTF-8 BOM, which corrupts non-ASCII text and can break parsing.
#
#  IMPORTANT 2: dev tools live on D: on purpose.
#    The C: drive is the system drive and must stay clean; the F: drive (project)
#    has little free space. D: has the most room, so all heavy tooling goes there.
#      D:\devtools\jdk-21.0.12.1+1     JDK 21 LTS
#      D:\devtools\apache-maven-3.9.9  Maven
#      D:\devtools\m2repo              Maven local repository
#      D:\devtools\pgtool              portable PostgreSQL 16
#
#  IMPORTANT 3: memory is deliberately capped for a low-spec machine.
#    See db-start.ps1 (PostgreSQL) and backend-run.ps1 (JVM).
#
#  Usage:  . .\tools\dev-env.ps1
# =============================================================================

$script:DevToolRoot = 'D:\devtools'

$script:Jdk21Home  = Join-Path $script:DevToolRoot 'jdk-21.0.12.1+1'
$script:MavenHome  = Join-Path $script:DevToolRoot 'apache-maven-3.9.9'
$script:M2Repo     = Join-Path $script:DevToolRoot 'm2repo'
$script:PgHome     = Join-Path $script:DevToolRoot 'pgtool\pgsql'
$script:PgData     = Join-Path $script:DevToolRoot 'pgtool\data'
$script:PgPort     = 55432
$script:ProjectRoot = Split-Path -Parent $PSScriptRoot

function Test-DevTools {
    $missing = @()
    if (-not (Test-Path $script:Jdk21Home)) { $missing += "JDK 21  : $script:Jdk21Home" }
    if (-not (Test-Path $script:MavenHome)) { $missing += "Maven   : $script:MavenHome" }
    if (-not (Test-Path $script:PgHome))    { $missing += "Postgres: $script:PgHome" }
    if ($missing.Count -gt 0) {
        Write-Host 'Missing dev dependencies:' -ForegroundColor Yellow
        $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        Write-Host 'See docs round 09 for installation steps.' -ForegroundColor Yellow
        return $false
    }
    return $true
}

# JVM / Maven memory caps: keep the machine responsive
$env:JAVA_HOME = $script:Jdk21Home
$env:PATH = "$script:Jdk21Home\bin;$env:PATH"
$env:MAVEN_OPTS = '-Xmx512m -Dfile.encoding=UTF-8'

