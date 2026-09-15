output "volume_names" {
  description = "Names of the created libvirt volumes"
  value       = { for key, infrastructure in module.infrastructure : key => infrastructure.volume_name }
}

output "domain_names" {
  description = "Names of the created libvirt domains"
  value       = { for key, infrastructure in module.infrastructure : key => infrastructure.domain_name }
}

output "cloudinit_names" {
  description = "Names of the created cloud-init disks"
  value       = { for key, infrastructure in module.infrastructure : key => infrastructure.cloudinit_name }
}
