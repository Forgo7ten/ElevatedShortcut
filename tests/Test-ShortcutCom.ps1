# Windows-only, no UAC/task registration: exercise WScript.Shell on PS 5.1 and PS 7.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'Common.ps1')
Assert-Windows

$directory = Join-Path ([IO.Path]::GetTempPath()) ('ElevatedShortcutCom-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -Path $directory -ItemType Directory
try {
    $exe = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
    if (-not [IO.File]::Exists($exe)) { throw 'cmd.exe is missing from the Windows runner.' }
    $source = Join-Path $directory 'Demo App.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $original = $shell.CreateShortcut($source)
    $original.TargetPath = $exe
    $original.Arguments = '/c "echo test"'
    $original.WorkingDirectory = $directory
    $original.IconLocation = $exe + ',0'
    $original.Save()

    $spec = Resolve-Source $source
    if ($spec.TargetPath -ine $exe) { throw 'COM target extraction failed.' }
    if ($spec.Arguments -cne '/c "echo test"') { throw 'COM argument extraction failed.' }
    if ($spec.WorkingDirectory -ine $directory) { throw 'COM working directory extraction failed.' }
    if (-not $spec.IconLocation.EndsWith(',0')) { throw 'COM icon index extraction failed.' }
    Write-Host 'PASS: COM link resolution and spaces in name'

    if ($spec.SourcePath -cne $source) { throw 'Source link location was not preserved.' }
    if ($spec.SourceDirectory -cne $directory) { throw 'The selected LNK directory must be preserved.' }

    $id = Get-SpecId $spec
    $newShortcut = Save-ManagedShortcut $spec 'Fixed' $id
    if (-not (Test-IsManagedShortcut $newShortcut 'Fixed' $id)) { throw 'Managed shortcut validation failed.' }
    if ([IO.Path]::GetDirectoryName($newShortcut) -cne $directory) {
        throw 'A writable source LNK directory must be preferred.'
    }
    $again = Save-ManagedShortcut $spec 'Fixed' $id
    if ($again -cne $newShortcut) { throw 'Repeat creation did not reuse the managed shortcut.' }
    Write-Host 'PASS: generated link, custom icon and no-clobber reuse'

    # Simulate a source directory that cannot be created: a regular file
    # occupies the preferred path. The destination must be the fallback root,
    # with no extra "管理员快捷方式" folder.
    $blocked = Join-Path $directory 'blocked-path'
    [IO.File]::WriteAllText($blocked, 'not a directory')
    $fallback = Join-Path $directory 'fallback-desktop'
    $null = New-Item -Path $fallback -ItemType Directory
    $blockedSpec = [pscustomobject]@{
        SourcePath = (Join-Path $blocked 'Demo.exe')
        SourceDirectory = $blocked
        DisplayName = 'Blocked'
        TargetPath = $spec.TargetPath
        Arguments = $spec.Arguments
        WorkingDirectory = $spec.WorkingDirectory
        IconLocation = $spec.IconLocation
    }
    $fallbackLink = Save-ManagedShortcut $blockedSpec 'Fixed' $id $fallback
    if ([IO.Path]::GetDirectoryName($fallbackLink) -cne $fallback) {
        throw 'Fallback link was not written directly to fallback Desktop.'
    }
    if ([IO.Directory]::Exists((Join-Path $fallback '管理员快捷方式'))) {
        throw 'The old fallback subdirectory must not be created.'
    }
    Write-Host 'PASS: direct-desktop fallback on unwritable source'
}
finally {
    Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
}
