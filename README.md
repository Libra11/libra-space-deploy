# 阿里云 ECS 最小生产部署

这个目录定义当前阶段的最小部署边界：

- 云资源由 Terraform/ROS 创建和更新。
- 镜像由本地或 CI 构建后推送到 ACR。
- ECS 只运行应用容器，不自建 PostgreSQL 和 Redis。
- 数据库迁移用一次性容器执行，成功后再启动 `server`。

## 云资源

建议先创建这些资源：

1. VPC、交换机、安全组。
2. ACR 企业版或个人版镜像仓库。当前采用方案 A：继续使用已有河源个人版 ACR，北京 ECS 跨地域拉取镜像。
3. RDS PostgreSQL。
4. Tair/Redis。
5. OSS Bucket。
6. ECS，安装 Docker 和 Docker Compose 插件。

安全组只暴露必要端口：

- `80` / `443`：Caddy 对外入口，自动申请和续期 HTTPS 证书。
- `22`：仅允许你的固定 IP 访问。
- `3000` / `8080`：不作为正式公网入口；调试期才按需开放。

RDS、Tair、OSS 访问优先使用同 VPC 内网地址。

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

填写 RDS、Tair、JWT、SMTP 等生产配置。不要把真实 `.env.server` 提交到仓库。

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
- 每次迁移前先创建 RDS 手动快照或确认自动备份可恢复。
- 禁止多个 server 副本在启动时并发执行迁移。
- 回滚优先回滚应用镜像；数据库结构回滚只在事故恢复时处理。
- 破坏性 schema 变更按 expand/contract 分两次发布。

## Terraform/ROS 分工

Terraform/ROS 只管理云资源，不直接管理应用版本：

- VPC、交换机、安全组。
- ACR 仓库。
- RDS 实例、账号、数据库、白名单。
- Tair/Redis 实例、白名单。
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
