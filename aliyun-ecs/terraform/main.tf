locals {
  prefix       = "${var.project_name}-${var.environment}"
  zone_id      = var.zone_id != "" ? var.zone_id : data.alicloud_zones.default.zones[0].id
  acr_registry = var.acr_registry != "" ? var.acr_registry : "registry.${var.region}.aliyuncs.com"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

data "alicloud_zones" "default" {
  available_disk_category     = var.ecs_system_disk_category
  available_resource_creation = "VSwitch"
  available_instance_type     = var.ecs_instance_type
}

data "alicloud_images" "ecs" {
  owners                  = "system"
  os_type                 = "linux"
  architecture            = "x86_64"
  instance_type           = var.ecs_instance_type
  name_regex              = var.ecs_image_id == "" ? var.ecs_image_name_regex : null
  image_id                = var.ecs_image_id == "" ? null : var.ecs_image_id
  is_support_cloud_init   = true
  is_support_io_optimized = true
  most_recent             = true
}

resource "alicloud_vpc" "main" {
  vpc_name   = "${local.prefix}-vpc"
  cidr_block = var.vpc_cidr
}

resource "alicloud_vswitch" "main" {
  vswitch_name = "${local.prefix}-vsw"
  vpc_id       = alicloud_vpc.main.id
  cidr_block   = var.vswitch_cidr
  zone_id      = local.zone_id
}

resource "alicloud_vswitch" "data" {
  vswitch_name = "${local.prefix}-data-vsw"
  vpc_id       = alicloud_vpc.main.id
  cidr_block   = var.data_vswitch_cidr
  zone_id      = var.data_zone_id
}

resource "alicloud_security_group" "ecs" {
  security_group_name = "${local.prefix}-ecs-sg"
  description         = "Security group for Libra Space ECS."
  vpc_id              = alicloud_vpc.main.id
}

resource "alicloud_security_group_rule" "ssh" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "22/22"
  priority          = 1
  security_group_id = alicloud_security_group.ecs.id
  cidr_ip           = var.admin_cidr
}

resource "alicloud_security_group_rule" "http" {
  for_each = toset(["80/80", "443/443"])

  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = each.value
  priority          = 10
  security_group_id = alicloud_security_group.ecs.id
  cidr_ip           = var.public_http_cidr
}

resource "alicloud_security_group_rule" "debug_app_ports" {
  for_each = toset(["3000/3000", "8080/8080"])

  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = each.value
  priority          = 20
  security_group_id = alicloud_security_group.ecs.id
  cidr_ip           = var.admin_cidr
}

resource "alicloud_cr_namespace" "main" {
  count              = var.create_acr ? 1 : 0
  name               = var.acr_namespace
  auto_create        = false
  default_visibility = "PRIVATE"
}

resource "alicloud_cr_repo" "app" {
  for_each = var.create_acr ? toset(["libra-space-server", "libra-space-admin"]) : toset([])

  namespace = alicloud_cr_namespace.main[0].name
  name      = each.value
  summary   = each.value
  repo_type = "PRIVATE"
  detail    = "Libra Space ${each.value} image repository."
}

resource "alicloud_oss_bucket" "managed_storage" {
  bucket        = var.oss_bucket_name
  storage_class = "Standard"

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      server_side_encryption_rule,
    ]
  }
}

resource "alicloud_oss_bucket_acl" "managed_storage" {
  bucket = alicloud_oss_bucket.managed_storage.bucket
  acl    = "private"
}

resource "alicloud_oss_bucket_server_side_encryption" "managed_storage" {
  bucket        = alicloud_oss_bucket.managed_storage.bucket
  sse_algorithm = "AES256"
}

resource "alicloud_ram_role" "managed_storage_sts" {
  role_name   = "${local.prefix}-oss-sts"
  description = "Role assumed by Libra Space server to issue scoped OSS STS credentials."
  force       = true
  assume_role_policy_document = jsonencode({
    Version = "1"
    Statement = [
      merge({
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          RAM = [
            "acs:ram::${var.aliyun_account_id}:root"
          ]
        }
        }, var.sts_external_id == "" ? {} : {
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.sts_external_id
          }
        }
      })
    ]
  })
}

resource "alicloud_ram_policy" "managed_storage_oss" {
  policy_name = "${local.prefix}-managed-oss"
  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "oss:ListObjects"
        ]
        Resource = [
          "acs:oss:*:*:${alicloud_oss_bucket.managed_storage.bucket}"
        ]
        Condition = {
          StringLike = {
            "oss:Prefix" = [
              var.oss_root_prefix,
              "${var.oss_root_prefix}/*"
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "oss:GetObject",
          "oss:GetObjectMeta",
          "oss:PutObject",
          "oss:DeleteObject",
          "oss:AbortMultipartUpload",
          "oss:ListParts"
        ]
        Resource = [
          "acs:oss:*:*:${alicloud_oss_bucket.managed_storage.bucket}/${var.oss_root_prefix}/*"
        ]
      }
    ]
  })
  description = "Managed OSS permissions for Libra Space user object prefixes."
  force       = true
}

resource "alicloud_ram_role_policy_attachment" "managed_storage_oss" {
  role_name   = alicloud_ram_role.managed_storage_sts.role_name
  policy_name = alicloud_ram_policy.managed_storage_oss.policy_name
  policy_type = alicloud_ram_policy.managed_storage_oss.type
}

resource "alicloud_instance" "app" {
  availability_zone          = local.zone_id
  security_groups            = [alicloud_security_group.ecs.id]
  instance_type              = var.ecs_instance_type
  instance_charge_type       = "PrePaid"
  period_unit                = "Month"
  system_disk_category       = var.ecs_system_disk_category
  system_disk_size           = var.ecs_system_disk_size
  image_id                   = data.alicloud_images.ecs.images[0].id
  instance_name              = "${local.prefix}-ecs"
  host_name                  = replace("${local.prefix}-ecs", "_", "-")
  vswitch_id                 = alicloud_vswitch.main.id
  internet_max_bandwidth_out = var.ecs_internet_bandwidth_out
  key_name                   = var.ecs_key_pair_name
  password                   = var.ecs_password
  user_data = base64encode(templatefile("${path.module}/user-data.sh.tftpl", {
    project_name = var.project_name
  }))
  tags = local.tags

  lifecycle {
    ignore_changes = [
      force_delete,
      include_data_disks,
    ]
  }
}
