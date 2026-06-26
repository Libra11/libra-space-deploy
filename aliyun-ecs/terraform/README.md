# Terraform 基础设施

这个目录创建一套最小生产资源：

- VPC、VSwitch、安全组。
- 可选创建 ACR 命名空间和 `libra-space-server` / `libra-space-admin` 私有仓库。
- ECS 实例，并通过 cloud-init 安装 Docker 和 Docker Compose 插件。

## 前置条件

1. 本机或 Cloud Shell 已安装 Terraform。
2. 当前身份有创建 ECS、VPC 资源的权限；如果 `create_acr = true`，还需要 ACR 权限。
3. 已在 ACR 控制台设置镜像仓库登录密码。当前建议复用已有河源个人版 ACR，并保持 `create_acr = false`。
4. 已准备 ECS Key Pair，优先不要使用 ECS 密码。

## 准备变量

```bash
cp terraform.tfvars.example terraform.tfvars
```

填写 `terraform.tfvars`。注意：

- `*.tfvars` 已被 `.gitignore` 忽略，不要提交真实值。
- `.env.aliyun` 已被 `.gitignore` 忽略，可用于保存本机 Terraform 访问凭证。
- 可选的 `ecs_password` 会进入 Terraform state。生产环境建议把 state 放到受控 OSS backend，并开启最小权限访问。
- `admin_cidr` 必须改成你的固定公网 IP，避免把 SSH 和调试端口暴露给全网。
- `ecs_image_id` 可以留空，Terraform 会按 `ecs_image_name_regex` 自动选择最新的 Alibaba Cloud Linux 3 x86_64 公共镜像。

本地凭证文件：

```bash
cp env.aliyun.example .env.aliyun
```

填写：

```env
ALICLOUD_ACCESS_KEY="<access-key-id>"
ALICLOUD_SECRET_KEY="<access-key-secret>"
ALICLOUD_REGION="cn-beijing"
```

## 预览

```bash
../scripts/infra-plan.sh
```

## 创建

确认费用、规格和安全组后再执行：

```bash
../scripts/infra-apply.sh
```

创建完成后读取输出：

```bash
terraform output
```

PostgreSQL 由 ECS 上的 Docker Compose 自建，数据库账号写在 ECS 部署目录的 `.env.postgres`。把数据库连接串写入 ECS 上的 `deploy/aliyun-ecs/.env.server`：

```env
DATABASE_URL="postgresql://libra:<postgres-password>@postgres:5432/libra_space?schema=public"
```

## 发布应用

基础设施创建完成后，继续使用上层脚本：

```bash
ACR_REGISTRY=registry.cn-heyuan.aliyuncs.com \
ACR_NAMESPACE=<namespace> \
VERSION=<version> \
BUILD_PLATFORM=linux/amd64 \
./deploy/aliyun-ecs/scripts/build-push.sh
```

如果构建机访问 Docker Hub 不稳定，可以额外设置 `NODE_IMAGE` 指向可访问的 Node 22 Alpine 镜像。

然后登录 ECS，进入部署目录：

```bash
./scripts/deploy.sh
```
