#!/bin/sh

set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
deploy_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"
compose_file="$deploy_dir/docker-compose.prod.yml"
postgres_env="$deploy_dir/.env.postgres"
backup_env="$deploy_dir/.env.postgres-backup"
backup_dir="$deploy_dir/backups/postgres"

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

if [ ! -f "$postgres_env" ]; then
  echo "Missing $postgres_env." >&2
  exit 1
fi

if [ ! -f "$backup_env" ]; then
  echo "Missing $backup_env." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$postgres_env"
# shellcheck disable=SC1090
. "$backup_env"
set +a

require_env POSTGRES_DB
require_env POSTGRES_USER
require_env POSTGRES_PASSWORD
require_env OSS_BUCKET
require_env OSS_REGION
require_env OSS_ENDPOINT

OSS_PREFIX="$(printf '%s' "${OSS_PREFIX:-backups/postgres}" | sed 's#^/*##; s#/*$##')"
ALIYUN_CLI_PROFILE="${ALIYUN_CLI_PROFILE:-libra-postgres-backup}"
LOCAL_RETENTION_DAYS="${LOCAL_RETENTION_DAYS:-7}"

mkdir -p "$backup_dir"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
filename="${POSTGRES_DB}-${timestamp}.dump"
local_path="$backup_dir/$filename"

cd "$deploy_dir"

docker compose -f "$compose_file" exec -T \
  -e PGPASSWORD="$POSTGRES_PASSWORD" \
  postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -Z 9 \
  > "$local_path"

if [ ! -s "$local_path" ]; then
  echo "Backup file is empty: $local_path" >&2
  exit 1
fi

oss_url="oss://$OSS_BUCKET/$OSS_PREFIX/$filename"
aliyun --profile "$ALIYUN_CLI_PROFILE" oss cp "$local_path" "$oss_url" \
  --region "$OSS_REGION" \
  --endpoint "$OSS_ENDPOINT"

find "$backup_dir" -type f -name "${POSTGRES_DB}-*.dump" -mtime +"$LOCAL_RETENTION_DAYS" -delete

echo "Uploaded PostgreSQL backup to $oss_url"
