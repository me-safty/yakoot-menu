param()

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location $ProjectDir

$EnvPath = Join-Path $ProjectDir ".env.production"
if (Test-Path $EnvPath) {
	Get-Content $EnvPath | ForEach-Object {
		if ($_ -match '^\s*([^#][^=]+?)=(.*)$') {
			[Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), "Process")
		}
	}
}

$PublicIp = if ($env:PUBLIC_IP) { $env:PUBLIC_IP } else { "217.55.171.129" }
$PublicPocketBaseUrl = if ($env:PUBLIC_POCKETBASE_URL) { $env:PUBLIC_POCKETBASE_URL } else { "https://$PublicIp" }
$PocketBaseHttp = if ($env:POCKETBASE_HTTP) { $env:POCKETBASE_HTTP } else { "127.0.0.1:8091" }

if ($env:POCKETBASE_ORIGINS) {
	$Origins = $env:POCKETBASE_ORIGINS
} else {
	$OriginList = @($PublicPocketBaseUrl, "http://$PublicIp")
	if ($env:VPN_IP) {
		$OriginList += "http://$($env:VPN_IP):8092"
	}
	$Origins = $OriginList -join ","
}

$PocketBase = Join-Path $ProjectDir ".tools\pocketbase.exe"
if (-not (Test-Path $PocketBase)) {
	$PocketBase = Join-Path $ProjectDir ".tools\pocketbase"
}

$ArgsList = @(
	"serve",
	"--http=$PocketBaseHttp",
	"--dir=pb_data",
	"--migrationsDir=pb_migrations",
	"--publicDir=pb_public",
	"--origins=$Origins"
)

if ($env:PB_ENCRYPTION_KEY) {
	$ArgsList += "--encryptionEnv=PB_ENCRYPTION_KEY"
}

& $PocketBase @ArgsList
exit $LASTEXITCODE
