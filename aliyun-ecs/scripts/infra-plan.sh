#!/bin/sh

set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
terraform_dir="$(CDPATH= cd -- "$script_dir/../terraform" && pwd)"

cd "$terraform_dir"

if [ -f ".env.aliyun" ]; then
  set -a
  . ".env.aliyun"
  set +a
fi

terraform init
terraform plan -input=false
