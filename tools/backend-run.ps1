# Run backend in dev mode (port 8080)
#
# JVM memory is capped at 512 MB (see dev-env.ps1) so the machine stays usable.
# A department-level system with a handful of concurrent users fits easily.
. "$PSScriptRoot\dev-env.ps1"

if (-not (Test-DevTools)) { exit 1 }

Write-Host 'Starting backend on http://localhost:8080 ...' -ForegroundColor Cyan
Write-Host "JDK   : $script:Jdk21Home"
Write-Host "M2    : $script:M2Repo"
Write-Host ''

& "$script:MavenHome\bin\mvn.cmd" `
    "-Dmaven.repo.local=$script:M2Repo" `
    "-s" (Join-Path $script:ProjectRoot 'backend\settings.xml') `
    "-f" (Join-Path $script:ProjectRoot 'backend\pom.xml') `
    "-DskipTests" `
    "-Dspring-boot.run.jvmArguments=-Xms256m -Xmx512m -XX:MaxMetaspaceSize=192m -Duser.timezone=Asia/Shanghai -Dfile.encoding=UTF-8" `
    spring-boot:run

