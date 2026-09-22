<#
  secret-scan.ps1 -- stop live credentials from being committed or pushed.

  Why this exists
  ---------------
  This repo holds a hospital follow-up system that is deployed on a public HTTPS
  site, and the Android build (C11) is planned to run on GitHub CI, which means
  the repository will be pushed somewhere. A credential that reaches a git
  history is very hard to take back. This script is the gate in front of that.

  Usage
  -----
    .\tools\secret-scan.ps1                 # scan every git-tracked file
    .\tools\secret-scan.ps1 -Mode staged    # scan only staged files
    .\tools\secret-scan.ps1 -Mode path -Path C:\some\dir

  Exit codes:  0 = clean (warnings may still be printed)
               2 = BLOCK - a likely live credential was found
               1 = usage error

  Findings never print the secret itself; values are masked.

  NOTE: this file must stay pure ASCII (PowerShell 5.1 decodes BOM-less files
  as GBK, and non-ASCII characters here would break parsing).
#>
[CmdletBinding()]
param(
    [ValidateSet('tracked', 'staged', 'path')]
    [string]$Mode = 'tracked',

    [string]$Path = '',

    [int]$MaxFileKB = 2048,

    [switch]$NoWarn
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# Binary / generated files: nothing to read, and reading them wastes time.
$SkipExt = @('.jar', '.zip', '.7z', '.gz', '.tar', '.exe', '.dll', '.class', '.so', '.dylib',
             '.png', '.jpg', '.jpeg', '.gif', '.ico', '.webp', '.bmp', '.pdf',
             '.woff', '.woff2', '.ttf', '.eot', '.mp4', '.mp3', '.bin', '.lock', '.map')

# High-confidence patterns: a match is always a problem.
$BlockRules = @(
    @{ Name = 'private key block';    Regex = '-----BEGIN [A-Z ]*PRIVATE KEY-----' },
    @{ Name = 'AWS access key id';    Regex = 'AKIA[0-9A-Z]{16}' },
    @{ Name = 'GitHub token';         Regex = 'gh[pousr]_[A-Za-z0-9]{30,}' },
    @{ Name = 'OpenAI-style key';     Regex = 'sk-[A-Za-z0-9]{32,}' },
    @{ Name = 'Slack token';          Regex = 'xox[baprs]-[A-Za-z0-9-]{10,}' },
    @{ Name = 'DB URL with password'; Regex = '(jdbc:)?(postgres(ql)?|mysql|mongodb(\+srv)?)://[^:@\s/]+:[^@\s/]{3,}@' }
)

# A secret-looking key assigned a literal value.
$SecretKey = '(password|passwd|pwd|secret|token|api[-_]?key|access[-_]?key|private[-_]?key|' +
             'data[-_]?key|encryption[-_]?key|jwt[-_]?secret|client[-_]?secret|signing[-_]?key)'
$AssignRegex = "(?i)^\s*[-#/;]*\s*(?<key>[A-Za-z0-9_.\-]*$SecretKey[A-Za-z0-9_.\-]*)\s*[:=]\s*(?<val>.+?)\s*$"
$QuotedAssignRegex = '(?i)(?<key>[A-Za-z0-9_.\-]*' + $SecretKey + '[A-Za-z0-9_.\-]*)\s*[:=]\s*[''""](?<val>[^''""]{8,})[''""]'

# An assignment rule is only meaningful in configuration files. Running it over
# .java / .js / .vue / .ps1 produces nothing but noise: dependency injection
# (`this.passwordEncoder = passwordEncoder;`), function definitions
# (`changePassword: (old, new) => ...`) and comparisons (`newPassword === confirm`).
$ConfigExt = @('.yml', '.yaml', '.properties', '.ini', '.toml', '.conf', '.env', '.json', '.cfg')
$ConfigNameRegex = '(?i)(\.env|\.envrc)(\..*)?$|\.(example|template|sample|dist|orig)$'

# Test harnesses legitimately carry throwaway credentials (a deliberately wrong
# password, a temp account's new password). Findings there are reported as WARN
# instead of BLOCK, so the gate stays trustworthy and nobody is tempted to
# disable it. This is a deliberate trade-off, not an oversight: the
# high-confidence rules above (private keys, cloud tokens, DB URLs) still BLOCK
# everywhere, and the demo-password check still fires here as a WARN.
$TestFixtureRegex = '(?i)(smoke-test|[-_.]test\.|test\.ps1|ui-check|fault-drill|load-test|drill-)'

# Values that only look like secrets.
$PlaceholderRegex = '(?i)^(\$\{.*\}|\$[A-Za-z_][A-Za-z0-9_]*|%[A-Za-z_][A-Za-z0-9_]*%|<[^>]*>|)$'
$JunkRegex = '(?i)^(change[_-]?me.*|change[_-]?this.*|change[_-]?it.*|replace[_-]?me.*|' +
             'placeholder.*|example.*|sample.*|redacted|your[-_]?password.*|yourpassword.*|yoursecret.*|' +
             'xxx+|\*+|\.+|-+|todo|fixme|none|null|nil|false|true|' +
             'scram-sha-\d+|md5|bcrypt|pbkdf2.*|argon2.*|sha\d+|' +
             'test|testing|demo|dev|local|password|passwd|secret|token|' +
             '123456|12345678|admin|root)$|' +
             '.*(wrong|invalid|fake|dummy|bogus|notreal|deliberate).*'
$CodeCharRegex = '[()\[\]{};,]|=>|&&|\|\||==|!='

function Test-LiteralSecret {
    # A value counts as a live credential only when it cannot be code and does
    # not look like a placeholder. Two shapes qualify:
    #   - contains a digit (Followup@2026, Zx9Qw2xy8KpL, hex/base64 blobs)
    #   - long (>=24) mixed-case random text
    param([string]$Value)
    $v = $Value
    if ([string]::IsNullOrWhiteSpace($v)) { return $false }
    $v = $v.Trim().Trim("'").Trim('"').Trim()
    if ($v.Length -lt 8) { return $false }
    if ($v -match $PlaceholderRegex) { return $false }
    if ($v -match $JunkRegex) { return $false }
    if ($v -match $CodeCharRegex) { return $false }
    $hasDigit = $v -match '\d'
    $longRandom = ($v.Length -ge 24) -and ($v -cmatch '[a-z]') -and ($v -cmatch '[A-Z]')
    if (-not ($hasDigit -or $longRandom)) { return $false }
    return $true
}

# Historic demo password for the local seeder. The live accounts were rotated on
# 2026-09-22, so this is a warning (do not reuse in a new environment), not a block.
$DemoLiterals = @('Followup@2026')

function Invoke-GitList {
    # core.quotepath=false stops git from dumping non-ASCII names as
    # "docs/\346\226\207..." style escapes; the console encoding must be UTF-8
    # for PowerShell 5.1 to decode the pipe correctly.
    param([string[]]$GitArgs)
    $previous = $null
    try {
        $previous = [Console]::OutputEncoding
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    } catch { }
    try {
        $raw = & git -c core.quotepath=false @GitArgs 2>$null
    } finally {
        if ($previous) {
            try { [Console]::OutputEncoding = $previous } catch { }
        }
    }
    if ($null -eq $raw) { return @() }
    return @($raw | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-TargetFiles {
    param([string]$Mode, [string]$Path)

    if ($Mode -eq 'path') {
        if ([string]::IsNullOrWhiteSpace($Path)) { throw '-Mode path requires -Path <directory>' }
        if (-not (Test-Path -LiteralPath $Path)) { throw ("path not found: {0}" -f $Path) }
        return @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
    }

    if ($Mode -eq 'staged') {
        $names = @(Invoke-GitList -GitArgs @('diff', '--cached', '--name-only', '--diff-filter=ACM'))
    } else {
        $names = @(Invoke-GitList -GitArgs @('ls-files'))
    }

    $out = @()
    foreach ($n in $names) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        $full = Join-Path $ProjectRoot $n
        if (Test-Path -LiteralPath $full -PathType Leaf -ErrorAction SilentlyContinue) {
            $out += (Get-Item -LiteralPath $full)
        }
    }
    return $out
}

function Get-Masked {
    param([string]$Value)
    $v = $Value
    if ($v.Length -le 4) { return ('*' * $v.Length) + (" ({0} chars)" -f $v.Length) }
    return ($v.Substring(0, 2) + '...' + $v.Substring($v.Length - 1) + (" ({0} chars)" -f $v.Length))
}

$blockHits = @()
$warnHits = @()
$scanned = 0

$files = @(Get-TargetFiles -Mode $Mode -Path $Path)

foreach ($file in $files) {
    if ($SkipExt -contains $file.Extension.ToLower()) { continue }
    if ($file.Length -gt ($MaxFileKB * 1024)) { continue }

    $isDoc = $file.Extension.ToLower() -eq '.md'
    $rel = $file.FullName
    if ($rel.StartsWith($ProjectRoot)) { $rel = $rel.Substring($ProjectRoot.Length).TrimStart('\') }

    # This scanner documents the demo password in its own comments and in the
    # rule list below; reporting itself would train people to ignore the output.
    $isSelf = ($file.FullName -eq $PSCommandPath)

    try {
        $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction Stop)
    } catch {
        continue
    }
    $scanned++

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $lineNo = $i + 1
        $reported = $false

        foreach ($rule in $BlockRules) {
            if ($line -match $rule.Regex) {
                $blockHits += ('{0}:{1}  [{2}]  {3}' -f $rel, $lineNo, $rule.Name, (Get-Masked $matches[0]))
                $reported = $true
            }
        }

        $isConfig = ($ConfigExt -contains $file.Extension.ToLower()) -or ($file.Name -match $ConfigNameRegex)
        $isTemplate = $file.Name -match '(?i)\.(example|template|sample|dist|orig)$'
        $isTestFixture = $file.Name -match $TestFixtureRegex

        # Check EVERY assignment on the line, not just the first one: a line such
        # as `password = 'wrong-1'; realKey = 'Kq7Rz...'` must not slip through.
        $candidates = @()
        if ($isConfig) { $candidates += [regex]::Matches($line, $AssignRegex) }
        $candidates += [regex]::Matches($line, $QuotedAssignRegex)

        $seenOnLine = @{}
        foreach ($m in $candidates) {
            $key = $m.Groups['key'].Value
            $val = $m.Groups['val'].Value
            $dupe = $key + '|' + $val
            if ($seenOnLine.ContainsKey($dupe)) { continue }
            $seenOnLine[$dupe] = $true

            $trimmed = $val.Trim().Trim("'").Trim('"').Trim()
            $isDemoValue = $false
            foreach ($d in $DemoLiterals) {
                if ($trimmed -eq $d) { $isDemoValue = $true }
            }

            if ($isDemoValue) {
                $warnHits += ('{0}:{1}  [known demo password] key={2}  {3}' -f $rel, $lineNo, $key, (Get-Masked $val))
                $reported = $true
            } elseif (Test-LiteralSecret -Value $val) {
                if ($isTemplate) {
                    $warnHits += ('{0}:{1}  [template holds a literal-looking value] key={2}  {3}' -f $rel, $lineNo, $key, (Get-Masked $val))
                } elseif ($isTestFixture) {
                    $warnHits += ('{0}:{1}  [test fixture holds a literal value] key={2}  {3}' -f $rel, $lineNo, $key, (Get-Masked $val))
                } else {
                    $blockHits += ('{0}:{1}  [literal secret assignment] key={2}  {3}' -f $rel, $lineNo, $key, (Get-Masked $val))
                }
                $reported = $true
            }
        }

        if (-not $reported -and -not $isSelf) {
            foreach ($d in $DemoLiterals) {
                if ($line.Contains($d)) {
                    $warnHits += ('{0}:{1}  [known demo password in text]  {2}' -f $rel, $lineNo, $d)
                    break
                }
            }
        }
    }
}

Write-Host ''
Write-Host ('secret-scan [{0}]  files scanned: {1}' -f $Mode, $scanned)

if ($warnHits.Count -gt 0 -and -not $NoWarn) {
    Write-Host ''
    Write-Host ('WARN  {0} place(s) reference the historic demo password (live accounts were rotated' -f $warnHits.Count)
    Write-Host '      on 2026-09-22). Do NOT reuse it in any new environment.'
    foreach ($w in ($warnHits | Select-Object -First 8)) { Write-Host ('      ' + $w) }
    if ($warnHits.Count -gt 8) { Write-Host ('      ... and {0} more' -f ($warnHits.Count - 8)) }
}

if ($blockHits.Count -gt 0) {
    Write-Host ''
    Write-Host '#########################  BLOCK  #########################'
    Write-Host ('  {0} likely live credential(s) found:' -f $blockHits.Count)
    foreach ($b in $blockHits) { Write-Host ('    ' + $b) }
    Write-Host ''
    Write-Host '  Values are masked on purpose. Fix by moving the value into an'
    Write-Host '  environment variable or an ignored file (deploy/.env), then re-run.'
    Write-Host '  Never commit it: git history is permanent.'
    Write-Host '###########################################################'
    Write-Host ''
    exit 2
}

Write-Host '  result: PASS (no live credential detected)'
Write-Host ''
exit 0
