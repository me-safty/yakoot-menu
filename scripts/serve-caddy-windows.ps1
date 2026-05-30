param(
	[string]$ConfigPath
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location $ProjectDir

if (-not $ConfigPath) {
	$ConfigPath = Join-Path $ProjectDir "output\windows\Caddyfile"
}

& caddy run --config $ConfigPath --adapter caddyfile
exit $LASTEXITCODE
