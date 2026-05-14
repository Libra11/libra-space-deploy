# 阿里云 ECS 最小生产部署

这个目录定义当前阶段的最小部署边界：

- 云资源由 Terraform/ROS 创建和更新。
- 镜像由本地或 CI 构建后推送到 ACR。
- ECS 运行应用容器和自建 PostgreSQL；OSS 使用云托管服务。
- 数据库迁移用一次性容器执行，成功后再启动 `server`。

## 云资源

建议先创建这些资源：

1. VPC、交换机、安全组。
2. ACR 企业版或个人版镜像仓库。当前采用方案 A：继续使用已有河源个人版 ACR，北京 ECS 跨地域拉取镜像。
3. OSS Bucket。
4. ECS，安装 Docker 和 Docker Compose 插件。

安全组只暴露必要端口：

- `80` / `443`：Caddy 对外入口，自动申请和续期 HTTPS 证书。
- `22`：仅允许你的固定 IP 访问。
- `3000` / `8080`：不作为正式公网入口；调试期才按需开放。

OSS 访问优先使用同地域端点。PostgreSQL 只在 ECS Docker 网络内暴露，不开放公网端口。

## 成本策略

测试阶段可以使用按量付费，便于随时调整规格和释放资源。进入长期运行或正式上线前，应复核 ECS 等稳定负载资源的计费方式，优先切换为包年包月或合适的节省计划，避免长期按量计费造成不必要成本。

切换前确认：

- 规格、地域、可用区和磁盘容量已经稳定。
- 近期没有迁移到 ACK、多副本或更大规格的计划。
- ECS 磁盘、PostgreSQL OSS 备份、对象存储和公网流量成本已经单独核算。

## 未来扩容路线

当前方案定位为单机生产早期形态：ECS 运行 `postgres`、`server`、`admin`、`proxy` 容器，OSS 使用云托管服务。这个架构成本低、改动少，但 PostgreSQL 和应用同机运行，扩容应按阶段推进。

### 阶段 1：单机纵向扩容

适用场景：用户量增长但单机资源仍是主要瓶颈，发布和运维复杂度需要保持低。

操作方向：

- 升级 ECS CPU、内存和系统盘规格。
- 按数据库增长情况扩容 ECS 磁盘，并确认 OSS 备份可恢复。
- 继续使用当前 Docker Compose 部署方式。

优点是改动最小；缺点是仍然存在单 ECS 故障点。

### 阶段 2：多 ECS 横向扩容

适用场景：API 请求量上升，需要多台应用服务器分摊流量。

目标形态：

- 前置 SLB/ALB 作为公网入口。
- 多台 ECS 运行 `server` 容器。
- `admin` 静态资源迁移到 OSS + CDN，或保留独立静态服务。
- Caddy 不再作为唯一公网入口；可以移除，或仅作为单机内部反代。
- 多 ECS 后应迁到托管 PostgreSQL 或独立数据库主机，所有 `server` 实例共享同一套 PostgreSQL、OSS；如果引入分布式限流或缓存，再增加 Redis/Tair。

改造点：

- 当前 `server` 基本无状态，认证会话、业务数据已经在数据库或 OSS，适合横向扩展。
- 限流当前使用 `@nestjs/throttler` 默认内存存储，多实例下只能按单实例计数。扩展到多 ECS 前，应改为共享存储实现，例如 Redis/Tair。
- `.env.server` 不应继续手工复制到每台 ECS，建议改为自动化分发或接入云密钥管理。
- 数据库迁移继续保持一次性任务，只允许单实例执行 `prisma migrate deploy`。

### 阶段 3：ACK/Kubernetes

适用场景：需要弹性伸缩、滚动发布、多副本高可用、标准化回滚和更完整的观测能力。

目标形态：

- `server` 使用 Deployment + HPA。
- 数据库迁移使用独立 Job。
- 配置和密钥使用 ConfigMap/Secret，敏感配置优先接入 KMS。
- `admin` 使用 OSS + CDN，或作为独立 Deployment。
- 日志接入 SLS，指标和告警接入云监控或 Prometheus。
- 镜像发布使用固定版本 tag，禁止只依赖 `latest`。

迁移到 ACK 前，应先完成阶段 2 的关键改造，尤其是分布式限流、配置管理和静态资源外置。

## 镜像发布

日常按改动范围选择发布入口：

```bash
./deploy/aliyun-ecs/scripts/release-server.sh
./deploy/aliyun-ecs/scripts/release-admin.sh
./deploy/aliyun-ecs/scripts/release-all.sh
```

- `release-server.sh`：只构建并发布 server，保留当前 admin 镜像，会执行数据库迁移。
- `release-admin.sh`：只构建并发布 admin，保留当前 server 镜像，不执行数据库迁移。
- `release-all.sh`：同时构建并发布 server/admin，会执行数据库迁移。

这些脚本会在本机构建并推送镜像到 ACR，然后通过 Cloud Assistant 让 ECS 切换镜像并完成重启。

发布成功后，ECS 会自动清理本机未被容器使用、且超过 7 天的 Docker 镜像，降低系统盘持续增长风险。可通过环境变量调整：

```bash
PRUNE_LOCAL_IMAGES=false ./deploy/aliyun-ecs/scripts/release-all.sh
PRUNE_LOCAL_IMAGES_UNTIL=336h ./deploy/aliyun-ecs/scripts/release-all.sh
```

说明：

- `PRUNE_LOCAL_IMAGES=false`：关闭 ECS 本机镜像清理。
- `PRUNE_LOCAL_IMAGES_UNTIL=336h`：只清理未使用且超过 14 天的镜像。
- 当前正在运行的容器镜像不会被 `docker image prune` 删除。

ACR 远端仓库仍会保留每次发布的版本 Tag。建议在 ACR 控制台配置镜像版本保留策略，例如每个仓库保留最近 10 到 20 个版本，或保留最近 30 到 60 天。不要把发布 tag 固定成 `latest`，否则会削弱回滚和审计能力。

构建并推送镜像到 ACR：

```bash
ACR_REGISTRY=registry.cn-heyuan.aliyuncs.com \
ACR_NAMESPACE=<namespace> \
VERSION=<version> \
BUILD_PLATFORM=linux/amd64 \
./deploy/aliyun-ecs/scripts/build-push.sh
```

如果构建机访问 Docker Hub 不稳定，可以额外设置 `NODE_IMAGE` / `NGINX_IMAGE` 指向可访问的基础镜像。

脚本最后会输出 `SERVER_IMAGE` 和 `ADMIN_IMAGE`，复制到 ECS 上的 `.env`。

## ECS 部署

在 ECS 上准备 Compose 镜像变量：

```bash
cp compose.env.example .env
```

填写：

```env
SERVER_IMAGE=registry.cn-heyuan.aliyuncs.com/<namespace>/libra-space-server:<version>
ADMIN_IMAGE=registry.cn-heyuan.aliyuncs.com/<namespace>/libra-space-admin:<version>
```

准备服务运行变量：

```bash
cp env.server.example .env.server
```

填写 Compose 本地 PostgreSQL、JWT、SMTP、微信支付等生产配置。不要把真实 `.env.server` 提交到仓库。

准备 PostgreSQL 运行变量：

```bash
cp env.postgres.example .env.postgres
chmod 600 .env.postgres
```

`.env.server` 里的 `DATABASE_URL` 使用 Compose 服务名 `postgres`：

```env
DATABASE_URL="postgresql://libra:<postgres-password>@postgres:5432/libra_space?schema=public"
```

准备 PostgreSQL 到 OSS 的自动备份配置：

```bash
cp env.postgres-backup.example .env.postgres-backup
chmod 600 .env.postgres-backup
```

在 ECS 上给备份脚本配置 `aliyun` profile 后，加入 crontab：

```bash
17 3 * * * /opt/libra-space/scripts/backup-postgres-to-oss.sh >> /opt/libra-space/backups/postgres/backup.log 2>&1
```

微信 Native 支付需要把商户 API 证书私钥放到 ECS 的部署目录，并让容器只读挂载：

```bash
mkdir -p certs/wechat
chmod 700 certs/wechat
```

把微信商户平台下载的 `apiclient_key.pem` 放到：

```text
deploy/aliyun-ecs/certs/wechat/apiclient_key.pem
```

对应 `.env.server` 里保持容器内路径：

```env
BILLING_WECHAT_PAY_MERCHANT_PRIVATE_KEY_PATH="/app/certs/wechat/apiclient_key.pem"
```

`BILLING_WECHAT_PAY_NOTIFY_URL` 必须是公网 HTTPS 地址，例如：

```env
BILLING_WECHAT_PAY_NOTIFY_URL="https://space.penlibra.xin/api/billing/webhooks/wechat"
```

执行发布：

```bash
./scripts/deploy.sh
```

验证：

```bash
curl -fsS http://127.0.0.1/api/health
```

## 数据库升级原则

- 生产环境只执行 `prisma migrate deploy`。
- 每次迁移前先执行 `./scripts/backup-postgres-to-oss.sh`，确认 OSS 备份可恢复。
- 禁止多个 server 副本在启动时并发执行迁移。
- 回滚优先回滚应用镜像；数据库结构回滚只在事故恢复时处理。
- 破坏性 schema 变更按 expand/contract 分两次发布。

## Terraform/ROS 分工

Terraform/ROS 只管理云资源，不直接管理应用版本：

- VPC、交换机、安全组。
- ACR 仓库。
- OSS Bucket、RAM Role、STS 授权策略。
- ECS 实例和初始化脚本。

应用发布继续使用 ACR 镜像标签和 Compose。等需要多副本、滚动发布、弹性伸缩时，再迁移到 ACK + Helm。

当前 Terraform 骨架见：

- [terraform](./terraform/README.md)

基础设施预览和创建入口：

```bash
./scripts/infra-plan.sh
./scripts/infra-apply.sh
```
