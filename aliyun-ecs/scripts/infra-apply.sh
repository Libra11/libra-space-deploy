#!/bin/sh

set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
terraform_dir="$(CDPATH= cd -- "$script_dir/../terraform" && pwd)"

cat <<'EOF'
This will create or change Alibaba Cloud resources and may incur cost.
Type APPLY to continue:
EOF

read -r confirmation
if [ "$confirmation" != "APPLY" ]; then
  echo "Aborted."
  exit 1
fi

cd "$terraform_dir"

if [ -f ".env.aliyun" ]; then
  set -a
  . ".env.aliyun"
  set +a
fi

terraform init
terraform apply -input=false -auto-approve
