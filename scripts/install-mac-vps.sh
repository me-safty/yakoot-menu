#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUBLIC_IP="${PUBLIC_IP:-217.55.171.129}"
PB_HTTP="${POCKETBASE_HTTP:-127.0.0.1:8091}"
CERT_NAME="${CERT_NAME:-yakoot-ip}"
STAGING="${STAGING:-0}"
NGINX_HTTP_PORT="${NGINX_HTTP_PORT:-8080}"
NGINX_HTTPS_PORT="${NGINX_HTTPS_PORT:-8443}"
CERTBOT_CONFIG_DIR="${CERTBOT_CONFIG_DIR:-${PROJECT_DIR}/output/letsencrypt/config}"
CERTBOT_WORK_DIR="${CERTBOT_WORK_DIR:-${PROJECT_DIR}/output/letsencrypt/work}"
CERTBOT_LOGS_DIR="${CERTBOT_LOGS_DIR:-${PROJECT_DIR}/output/letsencrypt/logs}"
BREW_PREFIX="$(brew --prefix)"
NGINX_SERVERS_DIR="${BREW_PREFIX}/etc/nginx/servers"
NGINX_CONF="${BREW_PREFIX}/etc/nginx/nginx.conf"
NGINX_SITE_CONF="${NGINX_SERVERS_DIR}/yakoot.conf"
LAUNCH_AGENT_SRC="${PROJECT_DIR}/deploy/launchd/com.yakoot.pocketbase.plist"
LAUNCH_AGENT_DST="${HOME}/Library/LaunchAgents/com.yakoot.pocketbase.plist"

reload_or_start_nginx() {
	if "${BREW_PREFIX}/bin/nginx" -s reload 2>/dev/null; then
		return
	fi

	"${BREW_PREFIX}/bin/nginx"
}

cd "$PROJECT_DIR"

mkdir -p certbot-webroot output "$CERTBOT_CONFIG_DIR" "$CERTBOT_WORK_DIR" "$CERTBOT_LOGS_DIR" "${HOME}/Library/LaunchAgents"

if [[ ! -f ".env.production" ]]; then
	key="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
	{
		echo "PUBLIC_POCKETBASE_URL=https://${PUBLIC_IP}"
		echo "POCKETBASE_HTTP=${PB_HTTP}"
		echo "POCKETBASE_INTERNAL_URL=http://${PB_HTTP}"
		echo "PB_ENCRYPTION_KEY=${key}"
	} > ".env.production"
	chmod 600 ".env.production"
fi

if lsof -nP -iTCP:8090 -sTCP:LISTEN | awk 'NR > 1 && $1 ~ /^pocketbas/ { found = 1 } END { exit !found }'; then
	echo "Stop dev PocketBase on :8090 before deploy; same pb_data must not run twice." >&2
	exit 1
fi

port_8091_owner="$(lsof -nP -iTCP:8091 -sTCP:LISTEN | awk 'NR > 1 { print $1; exit }' || true)"
if [[ -n "$port_8091_owner" && "$port_8091_owner" != pocketbas* ]]; then
	echo "Port 8091 is already used by ${port_8091_owner}. Set POCKETBASE_HTTP before deploy." >&2
	exit 1
fi

if ! command -v nginx >/dev/null 2>&1 || ! command -v certbot >/dev/null 2>&1; then
	brew install nginx certbot
fi

pnpm run pb:install

cp "$LAUNCH_AGENT_SRC" "$LAUNCH_AGENT_DST"
launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_DST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_DST"
launchctl kickstart -k "gui/$(id -u)/com.yakoot.pocketbase"

mkdir -p "$NGINX_SERVERS_DIR"
if ! grep -q "include servers/\\*;" "$NGINX_CONF"; then
	echo "Missing nginx include: add 'include servers/*;' inside http {} in $NGINX_CONF" >&2
	exit 1
fi

cp "${PROJECT_DIR}/deploy/nginx/yakoot.bootstrap.conf" "$NGINX_SITE_CONF"
"${BREW_PREFIX}/bin/nginx" -t
reload_or_start_nginx

certbot_args=(
	certonly
	--non-interactive
	--agree-tos
	--register-unsafely-without-email
	--webroot
	--config-dir "$CERTBOT_CONFIG_DIR"
	--work-dir "$CERTBOT_WORK_DIR"
	--logs-dir "$CERTBOT_LOGS_DIR"
	--webroot-path "${PROJECT_DIR}/certbot-webroot"
	--preferred-profile shortlived
	--ip-address "$PUBLIC_IP"
	--cert-name "$CERT_NAME"
	--deploy-hook "${BREW_PREFIX}/bin/nginx -s reload"
)

if [[ "$STAGING" == "1" ]]; then
	certbot_args+=(--staging)
fi

"${BREW_PREFIX}/bin/certbot" "${certbot_args[@]}"

cp "${PROJECT_DIR}/deploy/nginx/yakoot.conf" "$NGINX_SITE_CONF"
"${BREW_PREFIX}/bin/nginx" -t
reload_or_start_nginx

PUBLIC_POCKETBASE_URL="https://${PUBLIC_IP}" POCKETBASE_INTERNAL_URL="http://${PB_HTTP}" pnpm run build

echo "Done: https://${PUBLIC_IP}"
echo "CMS:  http://100.120.48.75:8092/cms/"
echo "Direct local HTTPS port: https://${PUBLIC_IP}:${NGINX_HTTPS_PORT}"
