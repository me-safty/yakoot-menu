# Yakoot Windows VPS Deployment Guide

This guide deploys Yakoot on a Windows VPS.

Target result:

- Public website: `https://APP_HOST/`
- Public PocketBase file reads only: `https://APP_HOST/api/files/...`
- Public PocketBase admin/dashboard: blocked
- PocketBase listens only on localhost: `127.0.0.1:8091`
- CMS/admin access: SSH tunnel or VPN only
- Optional local CMS URL through tunnel: `http://127.0.0.1:8092/cms/`
- Nginx serves Astro static files from `dist/`
- Nginx terminates TLS

Use a real domain for Windows deployment. Windows ACME tooling is good for domain certificates, but IP-only trusted HTTPS is still not a good Windows path. If you need browser-trusted HTTPS on a raw IP, use a Linux VPS or a Windows ACME client you have confirmed supports ACME IP identifiers.

## 0. Assumptions

Windows VPS:

- Windows Server 2022/2025 preferred
- Administrator access
- Public IPv4
- Provider firewall/security group access

Install paths:

```powershell
$AppName = "yakoot"
$AppDir = "C:\yakoot\app"
$BaseDir = "C:\yakoot"
$NginxDir = "C:\nginx"
$AcmeWebroot = "C:\yakoot\acme-webroot"
$ScriptsDir = "C:\yakoot\scripts"
$LogsDir = "C:\yakoot\logs"
$BackupDir = "C:\yakoot\backups"
$CertDir = "C:\yakoot\certs"
$WinAcmeDir = "C:\win-acme"
```

Services:

```text
YakootPocketBase
YakootNginx
```

Public ports:

```text
80/tcp
443/tcp
```

Private ports:

```text
127.0.0.1:8091  PocketBase
127.0.0.1:8092  local-only CMS proxy
```

## 1. Choose host values

Open PowerShell as Administrator.

### Recommended: domain

```powershell
$AppHost = "example.com"
$CertName = $AppHost
$PublicPocketBaseUrl = "https://$AppHost"
```

Create DNS first:

```text
example.com  A  VPS_PUBLIC_IPV4
www          A  VPS_PUBLIC_IPV4    # optional
```

Wait until DNS resolves:

```powershell
Resolve-DnsName $AppHost
```

### IP-only fallback

Use this only for temporary HTTP testing.

```powershell
$PublicIp = (Invoke-RestMethod -Uri "https://ifconfig.me")
$AppHost = $PublicIp
$CertName = "yakoot-ip"
$PublicPocketBaseUrl = "https://$PublicIp"
```

For production HTTPS on Windows, get a domain and use the domain flow below.

## 2. Provider firewall

In the cloud provider dashboard:

- Allow `80/tcp` from anywhere
- Allow `443/tcp` from anywhere
- Allow `3389/tcp` only from your IP, or disable RDP after SSH works
- Allow `22/tcp` only from your IP if you enable OpenSSH Server
- Deny everything else
- Do not expose `8091` or `8092`

## 3. Windows firewall

Run as Administrator:

```powershell
New-NetFirewallRule -DisplayName "Yakoot HTTP 80" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80
New-NetFirewallRule -DisplayName "Yakoot HTTPS 443" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 443
```

Block PocketBase/CMS ports from public interfaces:

```powershell
New-NetFirewallRule -DisplayName "Block public PocketBase 8091" -Direction Inbound -Action Block -Protocol TCP -LocalPort 8091
New-NetFirewallRule -DisplayName "Block public CMS proxy 8092" -Direction Inbound -Action Block -Protocol TCP -LocalPort 8092
```

If RDP is enabled, restrict it to your IP:

```powershell
$MyIp = "YOUR_PUBLIC_IP"
Set-NetFirewallRule -DisplayGroup "Remote Desktop" -RemoteAddress $MyIp
```

If you do not need RDP after setup:

```powershell
Disable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

## 4. Install tools

Install Git, Node 22, NSSM, and 7-Zip:

```powershell
winget install --id Git.Git -e
winget install --id OpenJS.NodeJS.LTS -e
winget install --id NSSM.NSSM -e
winget install --id 7zip.7zip -e
```

Restart PowerShell, then verify:

```powershell
git --version
node --version
npm --version
nssm version
```

Enable pnpm:

```powershell
corepack enable
corepack prepare pnpm@latest --activate
pnpm --version
```

This repo needs Node `>=22.12.0`.

## 5. Install Nginx for Windows

Download Nginx stable:

```powershell
$NginxVersion = "1.30.2"
$NginxZip = "$env:TEMP\nginx-$NginxVersion.zip"
Invoke-WebRequest -Uri "https://nginx.org/download/nginx-$NginxVersion.zip" -OutFile $NginxZip
Expand-Archive -Path $NginxZip -DestinationPath "C:\" -Force
Rename-Item -Path "C:\nginx-$NginxVersion" -NewName "nginx" -Force
```

Create folders:

```powershell
New-Item -ItemType Directory -Force $BaseDir, $AcmeWebroot, $ScriptsDir, $LogsDir, $BackupDir, $CertDir, "$NginxDir\conf\conf.d" | Out-Null
```

Add `conf.d` include inside `C:\nginx\conf\nginx.conf`.

Open the file:

```powershell
notepad C:\nginx\conf\nginx.conf
```

Inside the `http { ... }` block, add:

```nginx
include conf.d/*.conf;
```

Test Nginx:

```powershell
& C:\nginx\nginx.exe -p C:\nginx -t
```

## 6. Clone project

```powershell
New-Item -ItemType Directory -Force C:\yakoot | Out-Null
git clone YOUR_REPO_URL $AppDir
Set-Location $AppDir
pnpm install --frozen-lockfile
```

If the repo is private, add a deploy key or authenticate Git first.

## 7. Install PocketBase manually

The current repo install script is not enough for Windows because PocketBase binary is `pocketbase.exe`.

Install the project-pinned PocketBase version:

```powershell
Set-Location $AppDir
New-Item -ItemType Directory -Force ".tools" | Out-Null

$PbVersion = "0.38.2"
$PbZip = "$env:TEMP\pocketbase_$PbVersion_windows_amd64.zip"
$PbUrl = "https://github.com/pocketbase/pocketbase/releases/download/v$PbVersion/pocketbase_$PbVersion_windows_amd64.zip"

Invoke-WebRequest -Uri $PbUrl -OutFile $PbZip
Expand-Archive -Path $PbZip -DestinationPath ".tools" -Force

Test-Path ".tools\pocketbase.exe"
```

Run migrations:

```powershell
& "$AppDir\.tools\pocketbase.exe" migrate up `
  --dir="$AppDir\pb_data" `
  --migrationsDir="$AppDir\pb_migrations" `
  --publicDir="$AppDir\pb_public"
```

## 8. Create secrets

Generate PocketBase encryption key:

```powershell
$PbKeyBytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($PbKeyBytes)
$PbEncryptionKey = [Convert]::ToBase64String($PbKeyBytes).Substring(0,32)
```

Store it as a machine environment variable:

```powershell
[Environment]::SetEnvironmentVariable("PB_ENCRYPTION_KEY", $PbEncryptionKey, "Machine")
[Environment]::SetEnvironmentVariable("GOMEMLIMIT", "512MiB", "Machine")
```

Do not print this key in logs or chat.

Store deployment values for future scripts:

```powershell
@"
`$AppHost = "$AppHost"
`$CertName = "$CertName"
`$PublicPocketBaseUrl = "$PublicPocketBaseUrl"
`$AppDir = "$AppDir"
`$NginxDir = "$NginxDir"
"@ | Set-Content -Path "$ScriptsDir\yakoot-env.ps1" -Encoding UTF8
```

## 9. PocketBase service

Create service with NSSM:

```powershell
$PbArgs = @(
  "serve",
  "--http=127.0.0.1:8091",
  "--dir=$AppDir\pb_data",
  "--migrationsDir=$AppDir\pb_migrations",
  "--publicDir=$AppDir\pb_public",
  "--origins=$PublicPocketBaseUrl,http://127.0.0.1:8092",
  "--encryptionEnv=PB_ENCRYPTION_KEY"
) -join " "

nssm install YakootPocketBase "$AppDir\.tools\pocketbase.exe"
nssm set YakootPocketBase AppDirectory "$AppDir"
nssm set YakootPocketBase AppParameters "$PbArgs"
nssm set YakootPocketBase AppStdout "$LogsDir\pocketbase.out.log"
nssm set YakootPocketBase AppStderr "$LogsDir\pocketbase.err.log"
nssm set YakootPocketBase AppRotateFiles 1
nssm set YakootPocketBase AppRotateOnline 1
nssm set YakootPocketBase AppRotateBytes 10485760
nssm set YakootPocketBase Start SERVICE_AUTO_START
nssm start YakootPocketBase
```

Verify:

```powershell
Get-Service YakootPocketBase
Invoke-WebRequest -Uri "http://127.0.0.1:8091/" -UseBasicParsing
```

Expected: `StatusCode : 200`.

## 10. Build Astro

```powershell
Set-Location $AppDir
$env:PUBLIC_POCKETBASE_URL = $PublicPocketBaseUrl
$env:POCKETBASE_INTERNAL_URL = "http://127.0.0.1:8091"
pnpm run build
```

Verify:

```powershell
Test-Path "$AppDir\dist\index.html"
```

## 11. Nginx bootstrap config

This serves HTTP and ACME challenge files before TLS is issued.

Create `C:\nginx\conf\conf.d\yakoot.conf`:

```powershell
$BootstrapNginx = @"
limit_req_zone `$binary_remote_addr zone=yakoot_files:10m rate=20r/s;

server {
    listen 80;
    server_name $AppHost;
    server_tokens off;
    client_max_body_size 50M;

    location ^~ /.well-known/acme-challenge/ {
        root C:/yakoot/acme-webroot;
        default_type text/plain;
    }

    location ^~ /api/files/ {
        limit_except GET {
            deny all;
        }

        limit_req zone=yakoot_files burst=40 nodelay;
        proxy_pass http://127.0.0.1:8091;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }

    location ^~ /api/ {
        return 404;
    }

    location = /cms {
        return 404;
    }

    location ^~ /cms/ {
        return 404;
    }

    location = /_/ {
        return 404;
    }

    location ^~ /_/ {
        return 404;
    }

    location / {
        root C:/yakoot/app/dist;
        limit_except GET {
            deny all;
        }
        try_files `$uri `$uri/ /index.html;
    }
}

server {
    listen 127.0.0.1:8092;
    server_name _;
    client_max_body_size 50M;

    location = / {
        return 302 /cms/;
    }

    location = /cms {
        return 301 /cms/;
    }

    location ^~ /cms/ {
        rewrite ^/cms/(.*)$ /_/`$1 break;
        proxy_pass http://127.0.0.1:8091;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8091;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }
}
"@

$BootstrapNginx | Set-Content -Path "C:\nginx\conf\conf.d\yakoot.conf" -Encoding UTF8
```

Test:

```powershell
& C:\nginx\nginx.exe -p C:\nginx -t
```

Install Nginx service:

```powershell
nssm install YakootNginx "C:\nginx\nginx.exe"
nssm set YakootNginx AppDirectory "C:\nginx"
nssm set YakootNginx AppParameters "-p C:\nginx"
nssm set YakootNginx AppStdout "$LogsDir\nginx.out.log"
nssm set YakootNginx AppStderr "$LogsDir\nginx.err.log"
nssm set YakootNginx Start SERVICE_AUTO_START
nssm start YakootNginx
```

Verify HTTP:

```powershell
Invoke-WebRequest -Uri "http://$AppHost/" -UseBasicParsing
Invoke-WebRequest -Uri "http://$AppHost/cms/" -UseBasicParsing -SkipHttpErrorCheck
Invoke-WebRequest -Uri "http://$AppHost/api/" -UseBasicParsing -SkipHttpErrorCheck
```

Expected:

- `/` -> `200`
- `/cms/` -> `404`
- `/api/` -> `404`

## 12. Install win-acme

This guide uses win-acme for Windows TLS. It creates and renews domain certificates and can run a reload script after renewals.

Download latest win-acme:

```powershell
$WinAcmeRelease = Invoke-RestMethod "https://api.github.com/repos/win-acme/win-acme/releases/latest"
$WinAcmeAsset = $WinAcmeRelease.assets |
  Where-Object { $_.name -match "x64.*\.zip$" } |
  Select-Object -First 1

$WinAcmeZip = "$env:TEMP\$($WinAcmeAsset.name)"
Invoke-WebRequest -Uri $WinAcmeAsset.browser_download_url -OutFile $WinAcmeZip

New-Item -ItemType Directory -Force $WinAcmeDir | Out-Null
Expand-Archive -Path $WinAcmeZip -DestinationPath $WinAcmeDir -Force
```

Verify:

```powershell
& "$WinAcmeDir\wacs.exe" --version
```

Create Nginx reload script for renewals:

```powershell
@"
& C:\nginx\nginx.exe -p C:\nginx -t
if (`$LASTEXITCODE -eq 0) {
  & C:\nginx\nginx.exe -p C:\nginx -s reload
}
"@ | Set-Content -Path "$ScriptsDir\reload-nginx.ps1" -Encoding UTF8
```

## 13. Issue domain TLS certificate

This requires a domain. Do not use this section with a raw IP address.

```powershell
& "$WinAcmeDir\wacs.exe" `
  --source manual `
  --host "$AppHost" `
  --validation filesystem `
  --webroot "$AcmeWebroot" `
  --store pemfiles `
  --pemfilespath "$CertDir" `
  --pemfilesname "$CertName" `
  --installation script `
  --script "$ScriptsDir\reload-nginx.ps1" `
  --accepttos
```

Expected files:

```text
C:\yakoot\certs\CERT_NAME-chain.pem
C:\yakoot\certs\CERT_NAME-key.pem
```

If you also need `www.example.com`, set:

```powershell
$AppHost = "example.com,www.example.com"
```

Then use `example.com` as the Nginx primary server name and add `www.example.com` beside it in `server_name`.

If certificate issuance fails:

- Confirm DNS points to this VPS
- Confirm provider firewall allows `80/tcp`
- Confirm Windows firewall allows `80/tcp`
- Confirm Nginx is running
- Confirm `http://APP_HOST/.well-known/acme-challenge/test` is reachable from another internet connection

### About IP-only HTTPS on Windows

Let's Encrypt IP certificates require ACME client support for IP identifiers. Certbot added this support, but Certbot Windows support is discontinued. On Windows VPS, the practical production answer is: use a domain. If raw-IP HTTPS is mandatory, use a Linux VPS or verify a Windows ACME client supports IP identifiers before building around it.

## 14. Final Nginx TLS config

Create final config:

```powershell
$FinalNginx = @"
limit_req_zone `$binary_remote_addr zone=yakoot_files:10m rate=20r/s;

server {
    listen 80;
    server_name $AppHost;
    server_tokens off;

    location ^~ /.well-known/acme-challenge/ {
        root C:/yakoot/acme-webroot;
        default_type text/plain;
    }

    location / {
        return 301 https://`$host`$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;
    server_name $AppHost;
    server_tokens off;
    client_max_body_size 50M;

    ssl_certificate C:/yakoot/certs/$CertName-chain.pem;
    ssl_certificate_key C:/yakoot/certs/$CertName-key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    root C:/yakoot/app/dist;
    index index.html;

    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;
    add_header Content-Security-Policy "default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; form-action 'self'; img-src 'self' data: blob:; font-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'; upgrade-insecure-requests" always;

    location ^~ /api/files/ {
        limit_except GET {
            deny all;
        }

        limit_req zone=yakoot_files burst=40 nodelay;
        proxy_pass http://127.0.0.1:8091;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }

    location ^~ /api/ {
        return 404;
    }

    location = /cms {
        return 404;
    }

    location ^~ /cms/ {
        return 404;
    }

    location = /_/ {
        return 404;
    }

    location ^~ /_/ {
        return 404;
    }

    location / {
        limit_except GET {
            deny all;
        }
        try_files `$uri `$uri/ /index.html;
    }
}

server {
    listen 127.0.0.1:8092;
    server_name _;
    client_max_body_size 50M;

    location = / {
        return 302 /cms/;
    }

    location = /cms {
        return 301 /cms/;
    }

    location ^~ /cms/ {
        rewrite ^/cms/(.*)$ /_/`$1 break;
        proxy_pass http://127.0.0.1:8091;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8091;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }
}
"@

$FinalNginx | Set-Content -Path "C:\nginx\conf\conf.d\yakoot.conf" -Encoding UTF8
```

Reload:

```powershell
& C:\nginx\nginx.exe -p C:\nginx -t
& C:\nginx\nginx.exe -p C:\nginx -s reload
```

If reload fails, restart the service:

```powershell
Restart-Service YakootNginx
```

For a real domain, optionally add HSTS after HTTPS is verified:

```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

Do not enable HSTS casually for IP-only deployment.

## 15. win-acme renewal task

win-acme usually creates a scheduled task during certificate creation. Verify it:

```powershell
Get-ScheduledTask | Where-Object { $_.TaskName -match "win-acme|wacs" }
```

If no task exists, create one:

```powershell
$RenewAction = New-ScheduledTaskAction `
  -Execute "$WinAcmeDir\wacs.exe" `
  -Argument "--renew --quiet"

$RenewTrigger = New-ScheduledTaskTrigger -Daily -At 03:00

Register-ScheduledTask `
  -TaskName "Yakoot win-acme Renew" `
  -Action $RenewAction `
  -Trigger $RenewTrigger `
  -RunLevel Highest `
  -User "SYSTEM" `
  -Force
```

Test renew:

```powershell
& "$WinAcmeDir\wacs.exe" --renew --force --verbose
```

## 16. CMS access through SSH tunnel

Install OpenSSH Server:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
New-NetFirewallRule -DisplayName "OpenSSH 22" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22
```

Restrict SSH to your IP in provider firewall and Windows firewall:

```powershell
$MyIp = "YOUR_PUBLIC_IP"
Set-NetFirewallRule -DisplayName "OpenSSH 22" -RemoteAddress $MyIp
```

From your local machine:

```bash
ssh -N -L 8092:127.0.0.1:8092 Administrator@APP_HOST
```

Open locally:

```text
http://127.0.0.1:8092/cms/
```

This is the PocketBase admin UI, mapped from `/cms/` to PocketBase `/_/`, but only through localhost tunnel.

For stronger security:

- Use SSH keys
- Disable SSH password login in `C:\ProgramData\ssh\sshd_config`
- Restrict `22/tcp` to your IP
- Use a VPN instead of public SSH if possible

## 17. PocketBase dashboard hardening

Open CMS through the SSH tunnel:

```text
http://127.0.0.1:8092/cms/
```

Recommended settings:

- Create superuser with strong password
- Enable MFA/OTP if email is configured
- Settings -> Application -> enable rate limiter
- Settings -> Application -> Superuser IPs: add `127.0.0.1`
- Settings -> Mail: configure SMTP before relying on email/OTP
- Settings -> Backups: configure remote backup if available

If superuser IP whitelist locks you out, reset from VPS:

```powershell
& "$AppDir\.tools\pocketbase.exe" superuser ips 127.0.0.1 --dir="$AppDir\pb_data"
Restart-Service YakootPocketBase
```

## 18. Verify public deployment

```powershell
Invoke-WebRequest -Uri "http://$AppHost/" -MaximumRedirection 0 -SkipHttpErrorCheck -UseBasicParsing
Invoke-WebRequest -Uri "https://$AppHost/" -UseBasicParsing
Invoke-WebRequest -Uri "https://$AppHost/cms/" -SkipHttpErrorCheck -UseBasicParsing
Invoke-WebRequest -Uri "https://$AppHost/_/" -SkipHttpErrorCheck -UseBasicParsing
Invoke-WebRequest -Uri "https://$AppHost/api/" -SkipHttpErrorCheck -UseBasicParsing
```

Expected:

- `http://.../` -> `301`
- `https://.../` -> `200`
- `/cms/` -> `404`
- `/_/` -> `404`
- `/api/` -> `404`

Verify private ports:

```powershell
netstat -ano | findstr ":80 :443 :8091 :8092"
```

Expected:

- `0.0.0.0:80` or `[::]:80` for Nginx
- `0.0.0.0:443` or `[::]:443` for Nginx
- `127.0.0.1:8091` for PocketBase
- `127.0.0.1:8092` for local CMS proxy

## 19. Update deploy script

Create `C:\yakoot\scripts\deploy-yakoot.ps1`:

```powershell
@"
. C:\yakoot\scripts\yakoot-env.ps1

Set-Location `$AppDir

git pull --ff-only
pnpm install --frozen-lockfile

Stop-Service YakootPocketBase
& "`$AppDir\.tools\pocketbase.exe" migrate up `
  --dir="`$AppDir\pb_data" `
  --migrationsDir="`$AppDir\pb_migrations" `
  --publicDir="`$AppDir\pb_public"
Start-Service YakootPocketBase

`$env:PUBLIC_POCKETBASE_URL = `$PublicPocketBaseUrl
`$env:POCKETBASE_INTERNAL_URL = "http://127.0.0.1:8091"
pnpm run build

& C:\nginx\nginx.exe -p C:\nginx -t
& C:\nginx\nginx.exe -p C:\nginx -s reload

Get-Service YakootPocketBase
Get-Service YakootNginx
"@ | Set-Content -Path "$ScriptsDir\deploy-yakoot.ps1" -Encoding UTF8
```

Run deploy:

```powershell
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File C:\yakoot\scripts\deploy-yakoot.ps1
```

## 20. Backups

Minimum backup:

- `C:\yakoot\app\pb_data`
- `C:\yakoot\scripts\yakoot-env.ps1`
- `C:\nginx\conf\conf.d\yakoot.conf`
- `C:\Certbot`

Create backup script:

```powershell
@"
`$Stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
`$BackupRoot = "C:\yakoot\backups"
`$AppDir = "C:\yakoot\app"

New-Item -ItemType Directory -Force `$BackupRoot | Out-Null

Stop-Service YakootPocketBase
Compress-Archive -Path "`$AppDir\pb_data" -DestinationPath "`$BackupRoot\pb_data-`$Stamp.zip" -Force
Start-Service YakootPocketBase

Compress-Archive -Path `
  "C:\yakoot\scripts\yakoot-env.ps1", `
  "C:\nginx\conf\conf.d\yakoot.conf", `
  "C:\Certbot" `
  -DestinationPath "`$BackupRoot\config-`$Stamp.zip" `
  -Force

Get-ChildItem `$BackupRoot -File |
  Where-Object { `$_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
  Remove-Item -Force
"@ | Set-Content -Path "$ScriptsDir\backup-yakoot.ps1" -Encoding UTF8
```

Create scheduled task:

```powershell
$BackupAction = New-ScheduledTaskAction `
  -Execute "PowerShell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\yakoot\scripts\backup-yakoot.ps1"

$BackupTrigger = New-ScheduledTaskTrigger -Daily -At 03:30

Register-ScheduledTask `
  -TaskName "Yakoot Backup" `
  -Action $BackupAction `
  -Trigger $BackupTrigger `
  -RunLevel Highest `
  -User "SYSTEM" `
  -Force
```

Local backups are not enough. Copy backups off the VPS.

Example from your local machine:

```powershell
scp Administrator@APP_HOST:C:/yakoot/backups/*.zip .\yakoot-vps-backups\
```

## 21. Restore backup

Upload backup:

```powershell
scp .\pb_data-YYYY-MM-DD-HHMMSS.zip Administrator@APP_HOST:C:/yakoot/restore/
```

On VPS:

```powershell
Stop-Service YakootPocketBase
Rename-Item -Path "C:\yakoot\app\pb_data" -NewName "pb_data.broken.$(Get-Date -Format yyyyMMddHHmmss)"
Expand-Archive -Path "C:\yakoot\restore\pb_data-YYYY-MM-DD-HHMMSS.zip" -DestinationPath "C:\yakoot\app" -Force
Start-Service YakootPocketBase
Get-Service YakootPocketBase
```

## 22. Logs and troubleshooting

Services:

```powershell
Get-Service YakootPocketBase
Get-Service YakootNginx
```

PocketBase logs:

```powershell
Get-Content C:\yakoot\logs\pocketbase.out.log -Tail 200
Get-Content C:\yakoot\logs\pocketbase.err.log -Tail 200
```

Nginx logs:

```powershell
Get-Content C:\nginx\logs\access.log -Tail 200
Get-Content C:\nginx\logs\error.log -Tail 200
Get-Content C:\yakoot\logs\nginx.err.log -Tail 200
```

Nginx config test:

```powershell
& C:\nginx\nginx.exe -p C:\nginx -t
```

Certbot:

```powershell
certbot certificates --config-dir C:\Certbot --work-dir C:\Certbot\work --logs-dir C:\Certbot\logs
Get-Content C:\Certbot\logs\letsencrypt.log -Tail 200
```

Port checks:

```powershell
netstat -ano | findstr ":80 :443 :8091 :8092"
```

External checks from another machine:

```bash
curl -I http://APP_HOST/
curl -I https://APP_HOST/
curl -I https://APP_HOST/cms/
curl -I https://APP_HOST/api/
```

## 23. Common failures

### Certbot timeout

Cause: Let's Encrypt cannot reach port `80`.

Check:

```powershell
Get-Service YakootNginx
Test-NetConnection -ComputerName $AppHost -Port 80
```

Also verify:

- Provider firewall allows `80/tcp`
- Windows firewall allows `80/tcp`
- Nginx config has ACME location
- DNS points to this VPS

### Browser shows certificate warning on IP

Cause: certificate is for a domain, but you opened the raw IP.

Fix:

- Open the domain, not IP
- Or issue IP certificate with Certbot 5.4+ and `--ip-address`

### Public `/cms` opens

Wrong config. Public Nginx must return `404` for:

```text
/cms
/cms/
/_/
/api/
```

Only local `127.0.0.1:8092/cms/` should open admin.

### PocketBase exposed publicly

Bad. Fix immediately:

```powershell
Stop-Service YakootPocketBase
```

Confirm PocketBase service args include:

```text
--http=127.0.0.1:8091
```

Restart:

```powershell
Start-Service YakootPocketBase
```

## 24. Security checklist

Before production:

- Domain used instead of IP if possible
- Provider firewall only exposes `80`, `443`, and restricted admin access
- Windows firewall allows only required inbound ports
- RDP restricted to your IP or disabled
- SSH restricted to your IP if enabled
- PocketBase bound to `127.0.0.1:8091`
- CMS proxy bound to `127.0.0.1:8092`
- Public `/cms`, `/_/`, `/api/` blocked
- Public `/api/files/` is read-only
- PocketBase rate limiter enabled
- PocketBase superuser IP whitelist enabled
- PocketBase MFA enabled if email configured
- Strong superuser password stored in password manager
- SMTP configured if email auth/OTP used
- Certbot renew scheduled task active
- Backups scheduled
- Backups copied off-server
- Restore tested
- Windows Update enabled
- Logs reviewed after deploy

## 25. Project notes

This Astro site is static. PocketBase reads happen at build time.

Use:

```powershell
$env:PUBLIC_POCKETBASE_URL = "https://$AppHost"
$env:POCKETBASE_INTERNAL_URL = "http://127.0.0.1:8091"
pnpm run build
```

`PUBLIC_POCKETBASE_URL` is used for browser-visible URLs.

`POCKETBASE_INTERNAL_URL` is used by Astro on the VPS during build.

If you later add public login, forms, writes, realtime, or client-side PocketBase SDK calls, the public Nginx policy must change. Right now it intentionally blocks public PocketBase API except `/api/files/`.

## References

- PocketBase docs: https://pocketbase.io/docs/
- PocketBase production guide: https://pocketbase.io/docs/going-to-production/
- Astro deployment docs: https://docs.astro.build/en/guides/deploy/
- Certbot Windows instructions: https://certbot.eff.org/instructions?os=windows&ws=other
- Let's Encrypt IP certificates in Certbot: https://letsencrypt.org/2026/03/11/shorter-certs-certbot/
- Nginx Windows docs: https://nginx.org/en/docs/windows.html
- Nginx proxy docs: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
