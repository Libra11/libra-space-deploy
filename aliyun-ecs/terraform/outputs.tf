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

output "local_postgres_database_url_template" {
  description = "Compose-local PostgreSQL DATABASE_URL template. Replace <password> with .env.postgres POSTGRES_PASSWORD."
  value       = "postgresql://libra:<password>@postgres:5432/libra_space?schema=public"
}

output "esa_site_id" {
  description = "ESA site ID when global acceleration is enabled."
  value       = try(alicloud_esa_site.public[0].id, "")
}

output "esa_website_record" {
  description = "ESA website record ID when global acceleration is enabled."
  value       = try(alicloud_esa_record.website[0].id, "")
}

output "esa_api_record" {
  description = "ESA API record ID when global acceleration is enabled."
  value       = try(alicloud_esa_record.api[0].id, "")
}
