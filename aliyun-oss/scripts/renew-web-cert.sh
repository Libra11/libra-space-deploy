#!/bin/sh

set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
deploy_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../../.." && pwd)"
aliyun_env="$repo_root/deploy/aliyun-ecs/terraform/.env.aliyun"
oss_env="$deploy_dir/.env.oss"
cert_domain="${CERT_DOMAIN:-knora.penlibra.xin}"
cert_email="${CERT_EMAIL:-admin@penlibra.xin}"
certs_dir="$deploy_dir/.certs"
acme_home="$certs_dir/acme-home"
acme_src="$certs_dir/acme.sh-src"
cert_dir="$certs_dir/$cert_domain"
cert_xml="$cert_dir/oss-cname-certificate.xml"

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

if [ -f "$oss_env" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$oss_env"
  set +a
fi

OSS_REGION="${OSS_REGION:-${ALICLOUD_REGION:-cn-beijing}}"
OSS_ENDPOINT="${OSS_ENDPOINT:-oss-$OSS_REGION.aliyuncs.com}"

if [ -x "$repo_root/.tools/aliyun-cli/aliyun" ]; then
  aliyun_cli="$repo_root/.tools/aliyun-cli/aliyun"
else
  aliyun_cli="aliyun"
fi

require_env ALICLOUD_ACCESS_KEY
require_env ALICLOUD_SECRET_KEY
require_env OSS_BUCKET

mkdir -p "$certs_dir" "$acme_home" "$cert_dir"

if [ ! -x "$acme_src/acme.sh" ]; then
  rm -rf "$acme_src"
  git clone --depth 1 "https://github.com/acmesh-official/acme.sh.git" "$acme_src"
fi

export Ali_Key="$ALICLOUD_ACCESS_KEY"
export Ali_Secret="$ALICLOUD_SECRET_KEY"

"$acme_src/acme.sh" --home "$acme_home" \
  --register-account \
  -m "$cert_email" \
  --server letsencrypt

"$acme_src/acme.sh" --home "$acme_home" \
  --issue \
  --dns dns_ali \
  -d "$cert_domain" \
  --server letsencrypt \
  --keylength ec-256

"$acme_src/acme.sh" --home "$acme_home" \
  --install-cert \
  -d "$cert_domain" \
  --ecc \
  --key-file "$cert_dir/privkey.pem" \
  --fullchain-file "$cert_dir/fullchain.pem" \
  --cert-file "$cert_dir/cert.pem" \
  --ca-file "$cert_dir/ca.pem"

CERT_DOMAIN="$cert_domain" CERT_DIR="$cert_dir" CERT_XML="$cert_xml" node --input-type=module <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';

const certDomain = process.env.CERT_DOMAIN;
const certDir = process.env.CERT_DIR;
const certXml = process.env.CERT_XML;
const certificate = readFileSync(`${certDir}/fullchain.pem`, 'utf8').trim();
const privateKey = readFileSync(`${certDir}/privkey.pem`, 'utf8').trim();
const escapeXml = (value) => value
  .replaceAll('&', '&amp;')
  .replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;');

writeFileSync(certXml, `<?xml version="1.0" encoding="UTF-8"?>
<BucketCnameConfiguration>
  <Cname>
    <Domain>${certDomain}</Domain>
    <CertificateConfiguration>
      <Certificate>${escapeXml(certificate)}</Certificate>
      <PrivateKey>${escapeXml(privateKey)}</PrivateKey>
      <Force>true</Force>
    </CertificateConfiguration>
  </Cname>
</BucketCnameConfiguration>
`, { mode: 0o600 });
NODE

"$aliyun_cli" oss bucket-cname --method put --item certificate "oss://$OSS_BUCKET" "$cert_xml" \
  --region "$OSS_REGION" \
  --endpoint "$OSS_ENDPOINT" \
  --access-key-id "$ALICLOUD_ACCESS_KEY" \
  --access-key-secret "$ALICLOUD_SECRET_KEY"

openssl x509 -in "$cert_dir/fullchain.pem" -noout -subject -issuer -dates
