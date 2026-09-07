output "volume_name" {
  description = "Name of the created libvirt volume"
  value       = module.volume.volume_name
}

output "domain_name" {
  description = "Name of the created libvirt domain"
  value       = module.domain.domain_name
}

output "cloudinit_name" {
  description = "Name of the created cloud-init disk"
  value       = module.cloudinit.cloudinit_name
}

output "ip_address" {
  value = module.domain.ip_address # または libvirt_domain から参照した IP
}

output "role" {
  value = var.node.role
}