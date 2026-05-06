output "ecs_public_ip" {
  description = "ECS public IP. Empty when ecs_internet_bandwidth_out is 0."
  value       = try(alicloud_instance.app.public_ip, "")
}

output "ecs_private_ip" {
  description = "ECS private IP."
  value       = alicloud_instance.app.primary_ip_address
}

output "ecs_image_id" {
  description = "Resolved ECS image ID."
  value       = data.alicloud_images.ecs.images[0].id
}

output "ecs_image_name" {
  description = "Resolved ECS image name."
  value       = data.alicloud_images.ecs.images[0].name
}

output "acr_registry_hint" {
  description = "Registry domain to use when building image tags."
  value       = local.acr_registry
}

output "acr_namespace" {
  description = "ACR namespace."
  value       = var.acr_namespace
}

output "server_image_template" {
  description = "Server image tag template."
  value       = "${local.acr_registry}/${var.acr_namespace}/libra-space-server:<version>"
}

output "admin_image_template" {
  description = "Admin image tag template."
  value       = "${local.acr_registry}/${var.acr_namespace}/libra-space-admin:<version>"
}

output "database_url_template" {
  description = "DATABASE_URL template. Replace <password> before writing .env.server."
  value       = "postgresql://${alicloud_db_account.app.account_name}:<password>@${alicloud_db_instance.postgres.connection_string}:5432/${alicloud_db_database.app.data_base_name}?schema=public"
}

output "redis_url_template" {
  description = "REDIS_URL template. Replace <password> before writing .env.server."
  value       = "redis://:<password>@${alicloud_kvstore_instance.redis.connection_domain}:6379"
}

output "oss_bucket" {
  description = "Managed OSS bucket."
  value       = alicloud_oss_bucket.managed_storage.bucket
}

output "oss_endpoint" {
  description = "Managed OSS public endpoint for the selected region."
  value       = "https://oss-${var.region}.aliyuncs.com"
}

output "oss_region" {
  description = "Managed OSS region value used by the application."
  value       = "oss-${var.region}"
}

output "managed_storage_sts_role_arn" {
  description = "Role ARN to save in the admin managed-storage settings."
  value       = alicloud_ram_role.managed_storage_sts.arn
}

output "managed_storage_root_prefix" {
  description = "Root prefix to save in the admin managed-storage settings."
  value       = var.oss_root_prefix
}
