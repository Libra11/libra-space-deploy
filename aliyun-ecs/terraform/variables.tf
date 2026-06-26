variable "project_name" {
  type        = string
  description = "Project name used as the resource name prefix."
  default     = "libra-space"
}

variable "environment" {
  type        = string
  description = "Deployment environment name."
  default     = "prod"
}

variable "region" {
  type        = string
  description = "Alibaba Cloud region."
  default     = "cn-beijing"
}

variable "zone_id" {
  type        = string
  description = "Zone ID. Leave empty to select the first zone matching the ECS instance type."
  default     = ""
}

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed to SSH into ECS and access debug app ports."
}

variable "public_http_cidr" {
  type        = string
  description = "CIDR allowed to access HTTP/HTTPS."
  default     = "0.0.0.0/0"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block."
  default     = "172.16.0.0/16"
}

variable "vswitch_cidr" {
  type        = string
  description = "VSwitch CIDR block."
  default     = "172.16.1.0/24"
}

variable "data_zone_id" {
  type        = string
  description = "Reserved data subnet zone ID. Keep it separate from the ECS-oriented zone selection."
  default     = "cn-beijing-k"
}

variable "data_vswitch_cidr" {
  type        = string
  description = "Reserved data VSwitch CIDR block."
  default     = "172.16.2.0/24"
}

variable "ecs_image_id" {
  type        = string
  description = "Optional ECS image ID. Leave empty to auto-select the latest system image matching ecs_image_name_regex."
  default     = ""
}

variable "ecs_image_name_regex" {
  type        = string
  description = "System image name regex used when ecs_image_id is empty."
  default     = "^aliyun_3_x64_20G_alibase_.*\\.vhd$"
}

variable "ecs_instance_type" {
  type        = string
  description = "ECS instance type."
  default     = "ecs.e-c1m2.large"
}

variable "ecs_key_pair_name" {
  type        = string
  description = "Existing ECS key pair name for SSH login."
  default     = null
}

variable "ecs_password" {
  type        = string
  description = "Optional ECS root password. Prefer ecs_key_pair_name because this value is stored in Terraform state."
  default     = null
  sensitive   = true
}

variable "ecs_system_disk_category" {
  type        = string
  description = "ECS system disk category."
  default     = "cloud_essd"
}

variable "ecs_system_disk_size" {
  type        = number
  description = "ECS system disk size in GiB."
  default     = 40
}

variable "ecs_internet_bandwidth_out" {
  type        = number
  description = "ECS public outbound bandwidth in Mbps. Set to 0 to avoid public IP allocation."
  default     = 5
}

variable "acr_namespace" {
  type        = string
  description = "ACR namespace. Must be globally valid in the selected registry."
}

variable "acr_registry" {
  type        = string
  description = "ACR registry domain used for image tags. Leave empty to use the infrastructure region."
  default     = ""
}

variable "create_acr" {
  type        = bool
  description = "Create ACR namespace and repositories. Set to false until Container Registry is activated for the account."
  default     = true
}
