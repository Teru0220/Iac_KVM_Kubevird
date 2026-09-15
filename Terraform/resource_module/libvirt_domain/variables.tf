variable "node" {
  description = "Configuration for one node domain"
  type = object({
    domain_name        = string
    volume_name        = string
    image_path         = string
    volume_pool        = string
    volume_capacity    = number
    volume_format      = string
    volume_target      = any
    domain_memory      = number
    domain_memory_unit = string
    domain_vcpu        = number
    domain_type        = string
    disk_driver        = any
    disk_target        = any
    os                 = any
    cpu                = any
    features           = any
    devices            = any
  })
}

variable "volume_name" {
  description = "Name of the volume attached to the domain"
  type        = string
}

variable "cloudinit_volume_name" {
  description = "Name of the cloud-init volume attached to the domain"
  type        = string
}
