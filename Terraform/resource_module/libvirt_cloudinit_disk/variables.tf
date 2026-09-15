variable "node" {
  description = "Configuration for one node cloudinit disk"
  type = object({
    instance_id      = string
    hostname         = string
    cloudinit_name   = string
  })
}

variable "ssh_public_key" {
  description = "SSH public key rendered into cloud-init user data"
  type        = string
}

variable "cloudinit_user" {
  description = "User account created by cloud-init"
  type        = string
  default     = "ubuntu"
}

variable "user_password" {
  description = "Optional password for the cloud-init user during setup"
  type        = string
  default     = ""
}
