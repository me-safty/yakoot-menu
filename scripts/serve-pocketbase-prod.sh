#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

if [[ -f ".env.production" ]]; then
	set -a
	source ".env.production"
	set +a
fi

PUBLIC_POCKETBASE_URL="${PUBLIC_POCKETBASE_URL:-https://217.55.171.129}"
PB_HTTP="${POCKETBASE_HTTP:-127.0.0.1:8091}"
PB_ORIGINS="${POCKETBASE_ORIGINS:-${PUBLIC_POCKETBASE_URL},http://217.55.171.129,http://100.120.48.75:8092}"
args=(
	serve
	"--http=${PB_HTTP}"
	"--dir=pb_data"
	"--migrationsDir=pb_migrations"
	"--publicDir=pb_public"
	"--origins=${PB_ORIGINS}"
)

if [[ -n "${PB_ENCRYPTION_KEY:-}" ]]; then
	args+=("--encryptionEnv=PB_ENCRYPTION_KEY")
fi

exec ./.tools/pocketbase "${args[@]}"
