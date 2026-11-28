# The root CLI must be launchable by PowerShell 5.1 / 7 without installing tasks.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $root 'cli.ps1'
# The CLI writes help to the information stream. Capture *>&1 for robust assertions.
$helpOutput = & $cli help *>&1 | Out-String
if ($helpOutput -notmatch 'install' -or $helpOutput -notmatch 'tasks' -or
    $helpOutput -notmatch 'sendto-remove') {
    throw 'CLI help did not include the expected commands.'
}
if ($helpOutput -match '\bmigrate\b' -or $helpOutput -match '\brefresh\b') {
    throw 'CLI help included unsupported commands.'
}
$engine = (Get-Process -Id $PID).Path
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & $engine -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli migrate *>$null
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorAction
}
if ($exitCode -eq 0) {
    throw 'Unsupported command should fail with a non-zero exit code.'
}
foreach ($launcher in @('cli.bat', 'install.bat', 'uninstall.bat')) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $launcher) -PathType Leaf)) {
        throw "Launcher batch file is missing: $launcher"
    }
}
Write-Host 'PASS: root CLI help and launcher files'
