<#
.SYNOPSIS
    Create a UAC-free launcher next to an EXE or LNK using a preapproved scheduled task.
.EXAMPLE
    .\New-ElevatedShortcut.ps1 -Mode Fixed 'C:\Tools\App.exe'
.EXAMPLE
    .\New-ElevatedShortcut.ps1 -Mode Generic 'C:\Tools\App.lnk'
#>
[CmdletBinding()]
param(
    [ValidateSet('Fixed', 'Generic')]
    [string]$Mode = 'Fixed',
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$SourcePath
)

. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Windows

try {
    if (-not $SourcePath -or $SourcePath.Count -eq 0) { throw '请通过「发送到」选择 EXE/LNK 文件，或传入文件路径。' }
    Assert-InstalledLauncher
    $null = Get-InstalledSettings

    foreach ($path in $SourcePath) {
        $spec = Resolve-Source $path
        $id = Get-SpecId $spec
        if ($Mode -eq 'Fixed') {
            $name = Get-TaskName $Mode $id $spec
            $description = $script:TaskMarker + $id
            $taskMatches = $false
            try {
                $service = New-TaskService
                $folder = Get-ToolTaskFolder $service $false
                $existing = Find-RegisteredTask $folder $name
                if ($null -ne $existing) {
                    Assert-TaskMatches $existing $description $spec.TargetPath $spec.Arguments $spec.WorkingDirectory
                    $taskMatches = $true
                }
            }
            catch {
                # Some task ACLs disallow definition reads without an elevated token.
                # The elevated registration helper will revalidate, not overwrite, such tasks.
                Write-Verbose "无管理员权限时无法读取任务定义，将交由提权注册步骤核验：$($_.Exception.Message)"
            }
            if (-not $taskMatches) {
                $json = ConvertTo-Json -InputObject $spec -Depth 4 -Compress
                $payload = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($json))
                if (Test-IsElevated) {
                    $helper = Join-Path (Get-ToolRoot) 'Register-FixedTask.ps1'
                    if (-not [IO.File]::Exists($helper)) {
                        $helper = Join-Path $PSScriptRoot 'Register-FixedTask.ps1'
                    }
                    & $helper -SpecBase64 $payload
                    if (-not $?) { throw '计划任务注册失败。' }
                }
                else {
                    # Elevate GUI-subsystem wscript.exe instead of CUI PowerShell so UAC
                    # elevation never spawns a visible console or Windows Terminal window.
                    $wscript = Join-Path ([Environment]::GetFolderPath('System')) 'wscript.exe'
                    $launcher = Join-Path (Get-ToolRoot) 'Launcher.vbs'
                    $args = (Quote-WindowsPath $launcher) + ' register ' + $payload
                    $child = Start-Process -FilePath $wscript -ArgumentList $args -Verb RunAs -Wait -PassThru
                    if ($child.ExitCode -ne 0) { throw "计划任务注册失败或已取消 UAC 授权（退出码 $($child.ExitCode)）。" }
                }
            }
        }
        else {
            $null = Assert-GenericTaskRegistered
            $directory = Join-Path (Get-DataRoot) 'profiles'
            $null = New-Item -ItemType Directory -Path $directory -Force
            $profilePath = Join-Path $directory ($id + '.json')
            $profile = [ordered]@{
                schema = 1
                id = $id
                targetPath = $spec.TargetPath
                arguments = $spec.Arguments
                workingDirectory = $spec.WorkingDirectory
                sourcePath = $spec.SourcePath
            }
            # The generic profile is intentionally user-writable: it feeds an
            # unrestricted elevated execution capability. See SECURITY.md.
            Write-JsonFile $profilePath $profile
        }

        Write-Verbose ("源文件：{0}；首选输出目录：{1}" -f $spec.SourcePath, $spec.SourceDirectory)
        $shortcutPath = Save-ManagedShortcut $spec $Mode $id
        Save-ShortcutRecord $shortcutPath $Mode $id
        $modeLabel = $(if ($Mode -eq 'Generic') { '通用模式' } else { '固定模式' })
        Write-Host "[$modeLabel] 已生成快捷方式：$shortcutPath"
    }
}
catch {
    $message = [string]$_.Exception.Message
    Write-Host "创建管理员快捷方式失败：$message" -ForegroundColor Red
    try {
        $shell = New-Object -ComObject WScript.Shell
        # 4112 = MB_ICONERROR (16) + MB_SYSTEMMODAL (4096) so the dialog stays visible above Explorer.
        $null = $shell.Popup($message, 0, 'ElevatedShortcut', 4112)
    }
    catch { }
    exit 1
}
