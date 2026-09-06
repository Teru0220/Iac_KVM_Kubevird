variable "cloudinit_name" {
  description = "Name of the cloud-init volume"
  type        = string
}

variable "cloudinit_path" {
  description = "Path of the generated cloud-init ISO"
  type        = string
}

variable "volume_pool" {
  description = "Storage pool for the cloud-init volume"
  type        = string
}