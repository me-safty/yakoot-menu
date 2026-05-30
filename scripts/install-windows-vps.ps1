param(
	[string]$PublicIp = $env:PUBLIC_IP,
	[string]$VpnIp = $env:VPN_IP,
	[string]$PocketBaseHttp = $env:POCKETBASE_HTTP,
	[string]$CaddyHttpPort = $env:CADDY_HTTP_PORT,
	[string]$CaddyHttpsPort = $env:CADDY_HTTPS_PORT,
	[string]$CertName = $env:CERT_NAME,
	[switch]$Staging,
	[switch]$SkipCert
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location $ProjectDir

if (-not $PublicIp) { $PublicIp = "217.55.171.129" }
if (-not $PocketBaseHttp) { $PocketBaseHttp = "127.0.0.1:8091" }
if (-not $CaddyHttpPort) { $CaddyHttpPort = "8080" }
if (-not $CaddyHttpsPort) { $CaddyHttpsPort = "8443" }
if (-not $CertName) { $CertName = "yakoot-ip" }

$OutputDir = Join-Path $ProjectDir "output\windows"
$CertbotWebroot = Join-Path $ProjectDir "certbot-webroot"
$CertbotConfigDir = Join-Path $ProjectDir "output\letsencrypt\config"
$CertbotWorkDir = Join-Path $ProjectDir "output\letsencrypt\work"
$CertbotLogsDir = Join-Path $ProjectDir "output\letsencrypt\logs"
$CaddyfilePath = Join-Path $OutputDir "Caddyfile"

New-Item -ItemType Directory -Force -Path $OutputDir, $CertbotWebroot, $CertbotConfigDir, $CertbotWorkDir, $CertbotLogsDir | Out-Null

function Require-Command {
	param([string]$Name, [string]$InstallHint)

	if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
		throw "$Name not found. $InstallHint"
	}
}

function ConvertTo-CaddyPath {
	param([string]$Path)
	return ($Path -replace "\\", "/")
}

function Wait-Tcp {
	param([string]$HostName, [int]$Port, [int]$TimeoutSeconds = 30)

	$Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while ((Get-Date) -lt $Deadline) {
		$Client = New-Object Net.Sockets.TcpClient
		try {
			$Async = $Client.BeginConnect($HostName, $Port, $null, $null)
			if ($Async.AsyncWaitHandle.WaitOne(1000)) {
				$Client.EndConnect($Async)
				$Client.Close()
				return
			}
		} catch {
		} finally {
			$Client.Close()
		}
		Start-Sleep -Seconds 1
	}

	throw "Timed out waiting for $HostName`:$Port"
}

function Write-Caddyfile {
	param([bool]$UseTls)

	$DistPath = ConvertTo-CaddyPath (Join-Path $ProjectDir "dist")
	$WebrootPath = ConvertTo-CaddyPath $CertbotWebroot
	$PocketBaseUpstream = "http://$PocketBaseHttp"

	$VpnBlock = ""
	if ($VpnIp) {
		$VpnBlock = @"

http://${VpnIp}:8092 {
	handle / {
		redir /cms/
	}

	handle /cms {
		redir /cms/
	}

	handle /cms/* {
		uri strip_prefix /cms
		rewrite * /_{uri}
		reverse_proxy $PocketBaseUpstream
	}

	handle /api/* {
		reverse_proxy $PocketBaseUpstream
	}

	respond 404
}
"@
	}

	if ($UseTls) {
		$FullChain = ConvertTo-CaddyPath (Join-Path $CertbotConfigDir "live\$CertName\fullchain.pem")
		$PrivKey = ConvertTo-CaddyPath (Join-Path $CertbotConfigDir "live\$CertName\privkey.pem")
		$PublicBlock = @"
:$CaddyHttpPort {
	handle /.well-known/acme-challenge/* {
		root * $WebrootPath
		file_server
	}

	redir https://${PublicIp}{uri} permanent
}

:$CaddyHttpsPort {
	tls $FullChain $PrivKey
	root * $DistPath
	encode gzip

	header {
		X-Content-Type-Options nosniff
		Referrer-Policy strict-origin-when-cross-origin
		Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()"
	}

	@filesWrite {
		path /api/files/*
		not method GET HEAD
	}
	respond @filesWrite 405

	handle /api/files/* {
		reverse_proxy $PocketBaseUpstream
	}

	handle /api/* {
		respond 404
	}

	handle /cms {
		respond 404
	}

	handle /cms/* {
		respond 404
	}

	handle /_ {
		respond 404
	}

	handle /_/* {
		respond 404
	}

	try_files {path} {path}/ /index.html
	file_server
}
"@
	} else {
		$PublicBlock = @"
:$CaddyHttpPort {
	root * $DistPath
	encode gzip

	header {
		X-Content-Type-Options nosniff
		Referrer-Policy strict-origin-when-cross-origin
		Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()"
	}

	handle /.well-known/acme-challenge/* {
		root * $WebrootPath
		file_server
	}

	@filesWrite {
		path /api/files/*
		not method GET HEAD
	}
	respond @filesWrite 405

	handle /api/files/* {
		reverse_proxy $PocketBaseUpstream
	}

	handle /api/* {
		respond 404
	}

	handle /cms {
		respond 404
	}

	handle /cms/* {
		respond 404
	}

	handle /_ {
		respond 404
	}

	handle /_/* {
		respond 404
	}

	try_files {path} {path}/ /index.html
	file_server
}
"@
	}

	@"
{
	admin off
	auto_https off
}

$PublicBlock$VpnBlock
"@ | Set-Content -Path $CaddyfilePath -Encoding UTF8
}

function Get-PowerShellExe {
	$Pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
	if ($Pwsh) { return $Pwsh.Source }
	return (Get-Command powershell.exe).Source
}

function Register-YakootTask {
	param([string]$Name, [string]$ScriptPath)

	Stop-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
	Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction SilentlyContinue

	$PowerShellExe = Get-PowerShellExe
	$Action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
	$Trigger = New-ScheduledTaskTrigger -AtLogOn
	Register-ScheduledTask -TaskName $Name -Action $Action -Trigger $Trigger -Description "Yakoot local VPS service" -Force | Out-Null
	Start-ScheduledTask -TaskName $Name
}

Require-Command "node" "Install Node.js 22.12+."
Require-Command "pnpm" "Install pnpm: npm i -g pnpm"
Require-Command "caddy" "Install Caddy: winget install CaddyServer.Caddy"
if (-not $SkipCert) {
	Require-Command "certbot" "Install Certbot: winget install EFF.Certbot"
}

if (-not (Test-Path ".env.production")) {
	$Bytes = New-Object byte[] 24
	[Security.Cryptography.RandomNumberGenerator]::Fill($Bytes)
	$Key = ([Convert]::ToBase64String($Bytes) -replace "[^A-Za-z0-9]", "").PadRight(32, "0").Substring(0, 32)
	$Scheme = if ($SkipCert) { "http" } else { "https" }
	$Origins = @("${Scheme}://${PublicIp}", "http://${PublicIp}")
	if ($VpnIp) { $Origins += "http://${VpnIp}:8092" }

	@"
PUBLIC_POCKETBASE_URL=${Scheme}://${PublicIp}
POCKETBASE_HTTP=$PocketBaseHttp
POCKETBASE_INTERNAL_URL=http://$PocketBaseHttp
POCKETBASE_ORIGINS=$($Origins -join ",")
PB_ENCRYPTION_KEY=$Key
"@ | Set-Content -Path ".env.production" -Encoding UTF8
}

pnpm run pb:install

Register-YakootTask -Name "YakootPocketBase" -ScriptPath (Join-Path $ProjectDir "scripts\serve-pocketbase-prod.ps1")

$PocketBaseParts = $PocketBaseHttp -split ":"
$PocketBaseHost = $PocketBaseParts[0]
$PocketBasePort = [int]$PocketBaseParts[-1]
Wait-Tcp -HostName $PocketBaseHost -Port $PocketBasePort -TimeoutSeconds 45

$env:PUBLIC_POCKETBASE_URL = if ($SkipCert) { "http://$PublicIp" } else { "https://$PublicIp" }
$env:POCKETBASE_INTERNAL_URL = "http://$PocketBaseHttp"
pnpm exec astro build

Write-Caddyfile -UseTls:$false
Register-YakootTask -Name "YakootCaddy" -ScriptPath (Join-Path $ProjectDir "scripts\serve-caddy-windows.ps1")
Wait-Tcp -HostName "127.0.0.1" -Port ([int]$CaddyHttpPort) -TimeoutSeconds 30

if (-not $SkipCert) {
	$CertbotArgs = @(
		"certonly",
		"--non-interactive",
		"--agree-tos",
		"--register-unsafely-without-email",
		"--webroot",
		"--config-dir", $CertbotConfigDir,
		"--work-dir", $CertbotWorkDir,
		"--logs-dir", $CertbotLogsDir,
		"--webroot-path", $CertbotWebroot,
		"--preferred-profile", "shortlived",
		"--ip-address", $PublicIp,
		"--cert-name", $CertName
	)

	if ($Staging) { $CertbotArgs += "--staging" }

	& certbot @CertbotArgs
	if ($LASTEXITCODE -ne 0) {
		throw "Certbot failed. Public 80 must reach this Windows host on $CaddyHttpPort."
	}

	Write-Caddyfile -UseTls:$true
	Register-YakootTask -Name "YakootCaddy" -ScriptPath (Join-Path $ProjectDir "scripts\serve-caddy-windows.ps1")
	Wait-Tcp -HostName "127.0.0.1" -Port ([int]$CaddyHttpsPort) -TimeoutSeconds 30
	Write-Host "Done: https://$PublicIp"
} else {
	Write-Host "Done: http://$PublicIp"
}

if ($VpnIp) {
	Write-Host "CMS:  http://${VpnIp}:8092/cms/"
} else {
	Write-Host "CMS:  set -VpnIp <tailscale-ip> and rerun to enable VPN CMS."
}
