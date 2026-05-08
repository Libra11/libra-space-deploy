#!/bin/sh

set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
deploy_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../../.." && pwd)"
web_dir="$repo_root/libra-space-web"
out_dir="$web_dir/out"
aliyun_env="$repo_root/deploy/aliyun-ecs/terraform/.env.aliyun"
oss_env="$deploy_dir/.env.oss"
website_config="$deploy_dir/website.xml"

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

if [ -f "$aliyun_env" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$aliyun_env"
  set +a
fi

if [ -f "$oss_env" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$oss_env"
  set +a
fi

OSS_REGION="${OSS_REGION:-${ALICLOUD_REGION:-cn-beijing}}"
OSS_ENDPOINT="${OSS_ENDPOINT:-oss-$OSS_REGION.aliyuncs.com}"
OSS_PREFIX="$(printf '%s' "${OSS_PREFIX:-}" | sed 's#^/*##; s#/*$##')"
SKIP_INSTALL="${SKIP_INSTALL:-false}"
APPLY_WEBSITE_CONFIG="${APPLY_WEBSITE_CONFIG:-true}"
ALLOW_OSS_ROOT_DEPLOY="${ALLOW_OSS_ROOT_DEPLOY:-false}"

if [ -x "$repo_root/.tools/aliyun-cli/aliyun" ]; then
  aliyun_cli="$repo_root/.tools/aliyun-cli/aliyun"
else
  aliyun_cli="aliyun"
fi

require_env ALICLOUD_ACCESS_KEY
require_env ALICLOUD_SECRET_KEY
require_env OSS_BUCKET

if [ -z "$OSS_PREFIX" ] && ! is_true "$ALLOW_OSS_ROOT_DEPLOY"; then
  echo "Refusing to sync OSS bucket root with --delete." >&2
  echo "Set OSS_PREFIX or ALLOW_OSS_ROOT_DEPLOY=true in $oss_env." >&2
  exit 1
fi

if [ -z "$OSS_PREFIX" ]; then
  oss_url="oss://$OSS_BUCKET"
  static_url="oss://$OSS_BUCKET/_next/static/"
else
  oss_url="oss://$OSS_BUCKET/$OSS_PREFIX"
  static_url="oss://$OSS_BUCKET/$OSS_PREFIX/_next/static/"
fi

cd "$web_dir"

if ! is_true "$SKIP_INSTALL"; then
  echo "Installing web dependencies with npm ci."
  npm ci
fi

echo "Building static web site."
npm run build

if [ ! -f "$out_dir/index.html" ]; then
  echo "Static export missing: $out_dir/index.html" >&2
  exit 1
fi

echo "Syncing $out_dir to $oss_url."
"$aliyun_cli" oss sync "$out_dir/" "$oss_url/" \
  --delete \
  --force \
  --region "$OSS_REGION" \
  --endpoint "$OSS_ENDPOINT" \
  --access-key-id "$ALICLOUD_ACCESS_KEY" \
  --access-key-secret "$ALICLOUD_SECRET_KEY" \
  --meta "Cache-Control:no-cache"

echo "Removing OSS directory marker objects."
(
  cd "$out_dir"
  find . -type d ! -name . | while IFS= read -r marker_dir; do
    marker_key="$(printf '%s' "$marker_dir" | sed 's#^\./##')"
    "$aliyun_cli" oss rm "$oss_url/$marker_key/" \
      --force \
      --region "$OSS_REGION" \
      --endpoint "$OSS_ENDPOINT" \
      --access-key-id "$ALICLOUD_ACCESS_KEY" \
      --access-key-secret "$ALICLOUD_SECRET_KEY" || true
  done
)

echo "Setting immutable cache metadata for Next.js static assets."
"$aliyun_cli" oss set-meta "$static_url" \
  "Cache-Control:public,max-age=31536000,immutable" \
  --recursive \
  --force \
  --region "$OSS_REGION" \
  --endpoint "$OSS_ENDPOINT" \
  --access-key-id "$ALICLOUD_ACCESS_KEY" \
  --access-key-secret "$ALICLOUD_SECRET_KEY" || true

if is_true "$APPLY_WEBSITE_CONFIG" && [ -z "$OSS_PREFIX" ]; then
  echo "Applying OSS static website configuration."
  "$aliyun_cli" oss website --method put "oss://$OSS_BUCKET" "$website_config" \
    --region "$OSS_REGION" \
    --endpoint "$OSS_ENDPOINT" \
    --access-key-id "$ALICLOUD_ACCESS_KEY" \
    --access-key-secret "$ALICLOUD_SECRET_KEY"
elif is_true "$APPLY_WEBSITE_CONFIG"; then
  echo "Skipping website configuration because OSS_PREFIX is set: $OSS_PREFIX"
fi

echo "WEB_OSS_URL=$oss_url"
