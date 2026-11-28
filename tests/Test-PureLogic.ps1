[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'Common.ps1')

function Assert-Equal([object]$Actual, [object]$Expected, [string]$Case) {
    if ([string]$Actual -cne [string]$Expected) {
        throw "FAIL: $Case - actual '$Actual' != expected '$Expected'"
    }
    Write-Host "PASS: $Case"
}
function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) { throw "FAIL: $Case" }
    Write-Host "PASS: $Case"
}

Assert-Equal (Get-Hash24 'abc') 'ba7816bf8f01cfea414140de' 'SHA256 truncation'
Assert-True ((Get-Hash24 'x').Length -eq 24) 'ID length'
Assert-True ((Get-GenericTaskName) -match '^Generic-[0-9a-f]{24}$') 'Per-user generic task name'
$taskNameSpec = [pscustomobject]@{ TargetPath = 'C:\Program Files\Demo App\Demo.exe' }
Assert-Equal (Get-TaskName 'Fixed' '0123456789abcdef01234567' $taskNameSpec) 'Run-Demo-0123456789abcdef01234567' 'Readable Run task name'
$newNameInfo = Get-FixedTaskNameInfo 'Run-Demo-0123456789abcdef01234567'
Assert-Equal $newNameInfo.Id '0123456789abcdef01234567' 'Run task name ID parsing'
Assert-True ($null -eq (Get-FixedTaskNameInfo 'Other-0123456789abcdef01234567')) 'Reject non-Run task name prefix'
Assert-True ($null -eq (Get-FixedTaskNameInfo 'Run-App-not-a-hash')) 'Reject malformed Run task name'
Assert-Equal (Get-TaskDisplayToken ([pscustomobject]@{ TargetPath = 'C:\Tools\Demo*App?.exe' })) 'Demo_App' 'Task display token sanitization'
Assert-True ((Get-TaskSecurityDescriptor) -match '\(A;;FRFX;;;S-1-[^)]*\)') 'Restricted per-user task ACL'
Assert-True ((Get-FolderSecurityDescriptor) -match 'O:BAG:BAD:P') 'Admin-owned task folder ACL'
Assert-Equal (Get-OutputName 'Demo' 'Fixed') 'Demo (Admin)' 'Fixed display name'
Assert-Equal (Get-OutputName 'Demo' 'Generic') 'Demo(Admin-G)' 'Generic display name'
Assert-Equal (Quote-WindowsPath 'C:\hello world\app.exe') '"C:\hello world\app.exe"' 'Path quoting'

# Descriptions must be readable AND retain the machine-readable task identity on line 1.
$sampleId = '0123456789abcdef01234567'
$marker = 'ElevatedShortcut:' + $sampleId
$description = Get-FixedTaskDescription $sampleId ([pscustomobject]@{
    TargetPath = 'C:\Demo\app.exe'
    Arguments = '--profile default'
    WorkingDirectory = 'C:\Demo'
})
Assert-True (Test-TaskDescriptionIdentity $description $marker) 'Readable task description identity'
Assert-True (-not (Test-TaskDescriptionIdentity ($marker + 'X') $marker)) 'Reject marker prefix collision'
Assert-True ($description.Contains("`r`n应用：app.exe")) 'Readable application name in task description'
Assert-True ($description.Contains('目标程序：C:\Demo\app.exe')) 'Readable EXE path in description'
Assert-True ($description.Contains('启动参数：--profile default')) 'Readable arguments in description'
Assert-True ($description.Contains('工作目录：C:\Demo')) 'Readable working directory in description'
Assert-True ($description.Length -le 920) 'Description length bound'

$lnkSpec = [pscustomobject]@{
    SourcePath = 'C:\Users\Demo\Shortcuts\App.lnk'
    SourceDirectory = 'C:\Users\Demo\Shortcuts'
    TargetPath = 'C:\Program Files\Demo\App.exe'
}
$sourceFolders = @(Get-OutputDirectories $lnkSpec 'C:\Users\Demo\Desktop')
Assert-Equal $sourceFolders.Count 2 'LNK and desktop two candidate directories'
Assert-Equal $sourceFolders[0] 'C:\Users\Demo\Shortcuts' 'LNK must use its own directory, not target EXE directory'
Assert-Equal $sourceFolders[1] 'C:\Users\Demo\Desktop' 'Desktop direct fallback, no subfolder'
$exeSpec = [pscustomobject]@{
    SourcePath = 'C:\Tools\App.exe'
    SourceDirectory = 'C:\Tools'
}
$exeFolders = @(Get-OutputDirectories $exeSpec 'C:\Users\Demo\Desktop')
Assert-Equal $exeFolders[0] 'C:\Tools' 'EXE must use its own directory'
$sameFolders = @(Get-OutputDirectories $lnkSpec 'C:\Users\Demo\Shortcuts')
Assert-Equal $sameFolders.Count 1 'Do not duplicate source when source is Desktop'

$specA = [pscustomobject]@{
    TargetPath = 'C:\Demo\app.exe'; Arguments = '--a'; WorkingDirectory = 'C:\Demo'
}
$specB = [pscustomobject]@{
    TargetPath = 'c:\demo\APP.EXE'; Arguments = '--a'; WorkingDirectory = 'c:\demo'
}
$specC = [pscustomobject]@{
    TargetPath = 'C:\Demo\app.exe'; Arguments = '--b'; WorkingDirectory = 'C:\Demo'
}
Assert-Equal (Get-SpecId $specA) (Get-SpecId $specB) 'Path casing normalization'
Assert-True ((Get-SpecId $specA) -cne (Get-SpecId $specC)) 'Argument change creates different ID'

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('ElevatedShortcutTest-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tempDir
try {
    $fakeExe = Join-Path $tempDir 'demo.exe'
    [IO.File]::WriteAllBytes($fakeExe, [byte[]]@(77, 90)) # This tests validation only; not executed.
    Assert-True (Test-LocalExecutable $fakeExe) 'Local EXE allowed'
    Assert-True (-not (Test-LocalExecutable '\\server\share\demo.exe')) 'UNC EXE rejected'
    Assert-True (-not (Test-LocalExecutable (Join-Path $tempDir 'missing.exe'))) 'Missing EXE rejected'
    $file = Join-Path $tempDir 'unicode.json'
    Write-JsonFile $file ([ordered]@{name = '中文路径'; arguments = 'a "b"'})
    $read = Read-JsonFile $file
    Assert-Equal $read.name '中文路径' 'UTF8 JSON roundtrip'
    Assert-Equal $read.arguments 'a "b"' 'JSON quote preservation'
    $bytes = [IO.File]::ReadAllBytes($file)
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) 'JSON UTF8 no BOM'

    Assert-True (-not (Test-UsablePowerShellBinary 'C:\Users\Demo\AppData\Local\Microsoft\WindowsApps\pwsh.exe')) 'Store AppExecLink pwsh excluded'
    Assert-True (-not (Test-UsablePowerShellBinary 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.4.6.0_x64__8wekyb3d8bbwe\pwsh.exe')) 'WindowsApps package pwsh excluded'
    $resolvedEngine = Get-PowerShellPath
    Assert-True (Test-UsablePowerShellBinary $resolvedEngine) 'Resolved PowerShell engine is usable and outside WindowsApps'
}
finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

$repoRoot = Split-Path -Parent $PSScriptRoot
foreach ($ps1 in @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.ps1')) {
    $raw = [IO.File]::ReadAllBytes($ps1.FullName)
    Assert-True ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) ("UTF8 BOM preserved: " + $ps1.Name)
}
$vbsBytes = [IO.File]::ReadAllBytes((Join-Path (Join-Path $repoRoot 'src') 'Launcher.vbs'))
$nonAscii = @($vbsBytes | Where-Object { $_ -gt 0x7F })
Assert-Equal $nonAscii.Count 0 'Launcher.vbs remains pure ASCII for wscript compatibility'

Write-Host "Pure logic checks passed on $($PSVersionTable.PSVersion)."
