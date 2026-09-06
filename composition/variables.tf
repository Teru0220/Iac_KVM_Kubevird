variable "nodes" {
  description = "Node definitions with individual volume and domain settings"
  type = list(object({
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
    instance_id        = string
    hostname           = string
    cloudinit_name     = string
  }))
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key used by cloud-init"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
