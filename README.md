# Yakoot Menu

Astro restaurant menu site backed by PocketBase.

## Env

Copy `.env.example` to `.env` and set:

```sh
PUBLIC_POCKETBASE_URL=https://217.55.171.129
POCKETBASE_HTTP=127.0.0.1:8091
POCKETBASE_INTERNAL_URL=http://127.0.0.1:8091
```

Production local env is `.env.production`:

```sh
PUBLIC_POCKETBASE_URL=https://217.55.171.129
POCKETBASE_HTTP=127.0.0.1:8091
POCKETBASE_INTERNAL_URL=http://127.0.0.1:8091
POCKETBASE_ORIGINS=https://217.55.171.129,http://217.55.171.129
PB_ENCRYPTION_KEY=<32 chars>
```

## PocketBase

PocketBase CMS source is in repo:

- `pb_migrations/`: schema
- `scripts/install-pocketbase.mjs`: local binary installer
- `pb_data/`: local CMS data, ignored
- `.tools/pocketbase`: downloaded binary, ignored

Run:

```sh
pnpm run pb:install
pnpm run pb:serve
```

Admin UI via VPN only:

```txt
http://100.120.48.75:8092/cms/
```

The first launch creates `pb_data/` and applies migrations.

Tracked migration creates collection `categories`:

| Field | Type | Notes |
| --- | --- | --- |
| `name` | text | required |
| `menuImage` | file | required, max files 10, jpg/png/webp |
| `sort` | number | optional |
| `isActive` | bool | required |

Public list/view rule:

```txt
isActive = true
```

Tracked migration also creates collection `site_settings` for footer and social links:

| Field | Type | Notes |
| --- | --- | --- |
| `logo` | file | optional, jpg/png/webp/svg |
| `hours` | text | required |
| `facebookUrl` | url | optional |
| `instagramUrl` | url | optional |

Only one `site_settings` record can exist.

Public list/view rule:

```txt
public
```

Tracked migration creates collection `footer_addresses`:

| Field | Type | Notes |
| --- | --- | --- |
| `address` | text | required |
| `description` | text | optional |
| `phoneNumber` | text | required |
| `sort` | number | optional |
| `isActive` | bool | required |

Public list/view rule:

```txt
isActive = true
```

## Commands

```sh
pnpm dev
pnpm run pb:install
pnpm run pb:serve
pnpm run pb:serve:prod
pnpm run pb:serve:windows
pnpm run pb:serve:dev
pnpm run pb:migrate:windows
pnpm run dev:all
pnpm build
pnpm run deploy:build
pnpm run deploy:mac
pnpm run deploy:windows
pnpm run deploy:windows:http
pnpm run windows:stop
pnpm preview
```

## Mac VPS deploy

Public IP:

```txt
217.55.171.129
```

Ports:

```txt
public router: 80 -> Mac 8080, 443 -> Mac 8443
local Nginx: 8080, 8443
internal PocketBase: 127.0.0.1:8091
VPN CMS: 100.120.48.75:8092/cms/
```

Public Nginx exposes only:

```txt
/
/_astro/
/favicon.*
/api/files/
```

PocketBase dashboard and write APIs are VPN-only:

```txt
http://100.120.48.75:8092/cms/
```

Deploy script:

```sh
pnpm run deploy:mac
```

It installs/uses Homebrew `nginx` and `certbot`, starts PocketBase with `launchd`,
gets a short-lived Let's Encrypt IP cert, installs Nginx config, then builds Astro.

Before running it:

```txt
forward router 80 -> this Mac 8080
forward router 443 -> this Mac 8443
do not forward 8091
stop dev PocketBase on 8090
disable Mac sleep
```

Nginx files:

```txt
deploy/nginx/yakoot.bootstrap.conf
deploy/nginx/yakoot.conf
```

## Windows VPS deploy

Windows deploy uses Caddy instead of Nginx. It keeps the same security model:
public site/files only, PocketBase dashboard/API via VPN only.

Requirements:

```txt
Windows 10/11 or Windows Server
PowerShell 5.1+
Node.js 22.12+
pnpm
Caddy
Certbot, only for HTTPS/IP cert
Tailscale, only for VPN CMS
router access
```

Install tools:

```powershell
winget install OpenJS.NodeJS
npm i -g pnpm
winget install CaddyServer.Caddy
winget install EFF.Certbot
```

Router forwards:

```txt
public router: 80 -> Windows PC 8080
public router: 443 -> Windows PC 8443
do not forward 8091
do not forward 8092
```

Windows firewall, run PowerShell as admin:

```powershell
New-NetFirewallRule -DisplayName "Yakoot HTTP" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080
New-NetFirewallRule -DisplayName "Yakoot HTTPS" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8443
```

Deploy with HTTPS:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-windows-vps.ps1 -PublicIp 217.55.171.129 -VpnIp <tailscale-ip>
```

Deploy HTTP-only, useful before cert/router is ready:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-windows-vps.ps1 -PublicIp 217.55.171.129 -VpnIp <tailscale-ip> -SkipCert
```

The script:

```txt
installs .tools\pocketbase.exe
creates .env.production if missing
starts PocketBase on 127.0.0.1:8091
builds Astro into dist/
starts Caddy on 8080 and 8443
creates scheduled tasks: YakootPocketBase, YakootCaddy
```

Windows URLs:

```txt
public site: https://217.55.171.129
HTTP-only fallback: http://217.55.171.129
VPN CMS: http://<tailscale-ip>:8092/cms/
```

Stop Windows services:

```powershell
pnpm run windows:stop
```

Remove Windows scheduled tasks:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\stop-windows-vps.ps1 -Unregister
```

Generated Windows Caddy config:

```txt
output/windows/Caddyfile
```

Notes:

```txt
Certbot HTTPS needs public port 80 reachable from the internet.
The scheduled tasks start at user logon.
For unattended Windows Server, edit tasks to run whether user is logged on or not.
Set -VpnIp to expose CMS on VPN; without it CMS is not exposed.
```
