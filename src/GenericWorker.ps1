# Invoked by the one preapproved highest-privilege generic scheduled task.
# SECURITY: this is an intentional arbitrary elevated EXE runner. See SECURITY.md.
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Windows

if (-not (Test-IsElevated)) { throw '通用任务工作进程必须以管理员权限运行。' }
Assert-GenericEnabled

$queue = Join-Path (Get-DataRoot) 'queue'
if (-not [IO.Directory]::Exists($queue)) { exit 0 }

# Parallel task instances are safe: each request is claimed by an atomic rename.
foreach ($item in @(Get-ChildItem -LiteralPath $queue -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
    $claimPath = Join-Path $queue ($item.BaseName + '.' + $PID + '.working')
    try {
        [IO.File]::Move($item.FullName, $claimPath)
    }
    catch [System.IO.IOException] { continue } # Another worker took it.
    try {
        $claimed = Get-Item -LiteralPath $claimPath
        if ($claimed.Length -gt 65536) { throw '请求数据过大。' }
        $request = Read-JsonFile $claimPath
        if ([int]$request.schema -ne 1) { throw '不支持的请求格式版本。' }
        if ([string]$request.id -cne [string]$item.BaseName) { throw '请求 ID 不匹配。' }
        $exe = [string]$request.targetPath
        $args = [string]$request.arguments
        $wd = [string]$request.workingDirectory
        if (-not (Test-LocalExecutable $exe)) { throw "目标不是本地已存在的 EXE 文件：$exe" }
        if (-not [IO.Directory]::Exists($wd)) { throw "工作目录无效：$wd" }
        if ($args.Length -gt 32768) { throw '启动参数超过最大长度限制。' }
        # Use ShellExecuteEx on the validated local .exe so console targets
        # (such as cmd.exe / powershell.exe) receive their own visible console
        # window instead of inheriting this worker's hidden console.
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $exe
        $startInfo.Arguments = $args
        $startInfo.WorkingDirectory = $wd
        $startInfo.UseShellExecute = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
    catch {
        # Don't elevate log-file writes into a user-controlled directory.
        # Failed requests are removed; see Task Scheduler's Operational event log.
        Write-Error -Message "通用启动请求执行失败（$($item.BaseName)）：$_" -ErrorAction Continue
    }
    finally {
        Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
    }
}
