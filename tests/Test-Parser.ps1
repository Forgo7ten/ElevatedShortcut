[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$scripts = @(Get-ChildItem -LiteralPath $repo -Recurse -File -Filter '*.ps1')
if ($scripts.Count -lt 5) { throw 'Too few scripts were discovered.' }
foreach ($script in $scripts) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $script.FullName, [ref]$tokens, [ref]$errors
    )
    if ($errors.Count -gt 0) {
        foreach ($errorItem in $errors) {
            Write-Error ("{0}: {1}" -f $script.FullName, $errorItem.Message)
        }
        throw "Parser errors in $($script.Name)"
    }
    Write-Host "PASS syntax: $($script.Name)"
}
Write-Host "Parser checks passed ($($scripts.Count) scripts) on $($PSVersionTable.PSVersion)"
