# 阿里云 OSS 官网部署

这个目录用于发布 `libra-space-web` 官网到阿里云 OSS 静态网站。

## 准备配置

复用 ECS 部署里的阿里云 AK 配置：

```bash
cp deploy/aliyun-ecs/terraform/env.aliyun.example deploy/aliyun-ecs/terraform/.env.aliyun
```

准备 OSS 发布配置：

```bash
cp deploy/aliyun-oss/env.oss.example deploy/aliyun-oss/.env.oss
```

填写：

```env
OSS_BUCKET="<globally-unique-oss-bucket-name>"
OSS_REGION="cn-beijing"
OSS_ENDPOINT="oss-cn-beijing.aliyuncs.com"
```

如果官网部署到 Bucket 根目录，设置：

```env
OSS_PREFIX=""
ALLOW_OSS_ROOT_DEPLOY="true"
```

脚本会使用 `--delete` 同步静态产物，远端多余对象会被删除。Bucket 根目录部署需要显式开启 `ALLOW_OSS_ROOT_DEPLOY`，避免误删同 Bucket 里的其他业务对象。

## 发布

```bash
./deploy/aliyun-oss/scripts/release-web.sh
```

也可以在 web 项目目录执行：

```bash
npm run deploy:oss
```

发布流程：

1. 执行 `npm ci`。
2. 执行 `next build`，生成静态目录 `libra-space-web/out`。
3. 同步 `out/` 到 `oss://$OSS_BUCKET/$OSS_PREFIX`。
4. 为 `_next/static/` 设置长期缓存。
5. 当 `OSS_PREFIX` 为空时，写入 OSS 静态网站配置：`index.html` 和 `404.html`。

## 常用变量

- `SKIP_INSTALL=true`：跳过 `npm ci`。
- `APPLY_WEBSITE_CONFIG=false`：不更新 OSS 静态网站配置。
- `OSS_PREFIX=website`：部署到 Bucket 子目录，适合已有 CDN 回源规则或多站点复用 Bucket。

## HTTPS 证书

`knora.penlibra.xin` 当前使用 Let's Encrypt 免费证书，并通过 OSS CNAME 证书配置启用 HTTPS。证书和私钥保存在本地忽略目录：

```bash
deploy/aliyun-oss/.certs/
```

续期并重新上传到 OSS：

```bash
./deploy/aliyun-oss/scripts/renew-web-cert.sh
```

可选变量：

- `CERT_DOMAIN=knora.penlibra.xin`：证书域名。
- `CERT_EMAIL=admin@penlibra.xin`：Let's Encrypt 账户联系邮箱。
