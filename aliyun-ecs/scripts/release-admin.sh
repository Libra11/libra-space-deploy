#!/bin/sh

set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../../.." && pwd)"
aliyun_env="$repo_root/deploy/aliyun-ecs/terraform/.env.aliyun"

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

if [ -f "$aliyun_env" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$aliyun_env"
  set +a
fi

VERSION="${VERSION:-$(date +%Y%m%d-%H%M%S)}"
ACR_REGISTRY="${ACR_REGISTRY:-registry.cn-heyuan.aliyuncs.com}"
ACR_NAMESPACE="${ACR_NAMESPACE:-libra-space-prod}"
ECS_REGION="${ECS_REGION:-${ALICLOUD_REGION:-cn-beijing}}"
ECS_INSTANCE_ID="${ECS_INSTANCE_ID:-i-2ze8uighngo391nxk3ix}"
NODE_IMAGE="${NODE_IMAGE:-docker.m.daocloud.io/library/node:22-alpine}"
NGINX_IMAGE="${NGINX_IMAGE:-docker.m.daocloud.io/library/nginx:alpine}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux/amd64}"
PRUNE_LOCAL_IMAGES="${PRUNE_LOCAL_IMAGES:-true}"
PRUNE_LOCAL_IMAGES_UNTIL="${PRUNE_LOCAL_IMAGES_UNTIL:-168h}"

admin_image="$ACR_REGISTRY/$ACR_NAMESPACE/libra-space-admin:$VERSION"

if [ -x "$repo_root/.tools/aliyun-cli/aliyun" ]; then
  aliyun_cli="$repo_root/.tools/aliyun-cli/aliyun"
else
  aliyun_cli="aliyun"
fi

require_env ALICLOUD_ACCESS_KEY
require_env ALICLOUD_SECRET_KEY

echo "Building admin image: $admin_image"
docker build \
  --platform "$BUILD_PLATFORM" \
  --build-arg NODE_IMAGE="$NODE_IMAGE" \
  --build-arg NGINX_IMAGE="$NGINX_IMAGE" \
  -t "$admin_image" \
  "$repo_root/libra-space-admin"

echo "Pushing admin image: $admin_image"
docker push "$admin_image"

remote_script=$(cat <<SCRIPT
#!/bin/sh
set -eu
cd /opt/libra-space
prune_local_images() {
  if [ '$PRUNE_LOCAL_IMAGES' = true ] || [ '$PRUNE_LOCAL_IMAGES' = TRUE ] || [ '$PRUNE_LOCAL_IMAGES' = 1 ] || [ '$PRUNE_LOCAL_IMAGES' = yes ] || [ '$PRUNE_LOCAL_IMAGES' = YES ]; then
    echo "Pruning unused Docker images older than $PRUNE_LOCAL_IMAGES_UNTIL."
    docker image prune -af --filter "until=$PRUNE_LOCAL_IMAGES_UNTIL" || true
    return
  fi

  echo "Skipping local Docker image prune. PRUNE_LOCAL_IMAGES=$PRUNE_LOCAL_IMAGES"
}
server_image="\$(awk -F= '/^SERVER_IMAGE=/ {print substr(\$0, index(\$0, \$2)); exit}' .env)"
if [ -z "\$server_image" ]; then
  echo "SERVER_IMAGE missing in /opt/libra-space/.env" >&2
  exit 1
fi
printf 'SERVER_IMAGE=%s\nADMIN_IMAGE=%s\n' "\$server_image" '$admin_image' > .env
docker compose -f docker-compose.prod.yml pull admin
docker compose -f docker-compose.prod.yml up -d --no-deps admin
docker compose -f docker-compose.prod.yml up -d --no-deps proxy
for _ in \$(seq 1 12); do
  if curl -fsS http://127.0.0.1/api/health >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
curl -fsS http://127.0.0.1/api/health >/dev/null
docker compose -f docker-compose.prod.yml ps
prune_local_images
SCRIPT
)

command_content="$(printf '%s' "$remote_script" | base64 | tr -d '\n')"

echo "Deploying admin image on ECS: $ECS_INSTANCE_ID"
invoke_id="$(
  ALIBABA_CLOUD_ACCESS_KEY_ID="$ALICLOUD_ACCESS_KEY" \
  ALIBABA_CLOUD_ACCESS_KEY_SECRET="$ALICLOUD_SECRET_KEY" \
  ALIBABA_CLOUD_REGION_ID="$ECS_REGION" \
  "$aliyun_cli" ecs RunCommand \
    --RegionId "$ECS_REGION" \
    --Type RunShellScript \
    --ContentEncoding Base64 \
    --CommandContent "$command_content" \
    --InstanceId.1 "$ECS_INSTANCE_ID" \
    --Timeout 900 \
    --Name "release-libra-space-admin-$VERSION" \
    --KeepCommand false \
  | jq -r '.InvokeId // .CommandId'
)"

if [ -z "$invoke_id" ] || [ "$invoke_id" = "null" ]; then
  echo "Failed to create ECS invocation." >&2
  exit 1
fi

echo "ECS invocation: $invoke_id"

for _ in $(seq 1 60); do
  result="$(
    ALIBABA_CLOUD_ACCESS_KEY_ID="$ALICLOUD_ACCESS_KEY" \
    ALIBABA_CLOUD_ACCESS_KEY_SECRET="$ALICLOUD_SECRET_KEY" \
    ALIBABA_CLOUD_REGION_ID="$ECS_REGION" \
    "$aliyun_cli" ecs DescribeInvocationResults \
      --RegionId "$ECS_REGION" \
      --InvokeId "$invoke_id" \
      --InstanceId "$ECS_INSTANCE_ID"
  )"
  invocation_status="$(printf '%s' "$result" | jq -r '.Invocation.InvocationResults.InvocationResult[0].InvocationStatus // .InvocationResults.InvocationResult[0].InvocationStatus // "Unknown"')"
  exit_code="$(printf '%s' "$result" | jq -r '.Invocation.InvocationResults.InvocationResult[0].ExitCode // .InvocationResults.InvocationResult[0].ExitCode // empty')"
  echo "ECS status: $invocation_status${exit_code:+, exit=$exit_code}"

  case "$invocation_status" in
    Success)
      printf '%s' "$result" \
        | jq -r '.Invocation.InvocationResults.InvocationResult[0].Output // .InvocationResults.InvocationResult[0].Output // empty' \
        | base64 -d 2>/dev/null \
        | tail -n 80 || true
      echo "ADMIN_IMAGE=$admin_image"
      exit 0
      ;;
    Failed|Stopped)
      printf '%s' "$result" \
        | jq -r '.Invocation.InvocationResults.InvocationResult[0].Output // .InvocationResults.InvocationResult[0].Output // empty' \
        | base64 -d 2>/dev/null \
        | tail -n 120 || true
      exit 1
      ;;
  esac

  sleep 10
done

echo "Timed out waiting for ECS deployment." >&2
exit 124
