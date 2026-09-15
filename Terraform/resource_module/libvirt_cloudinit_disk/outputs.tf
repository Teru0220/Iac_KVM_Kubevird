output "cloudinit_name" {
  description = "Name of the created libvirt cloudinit disk"
  value       = libvirt_cloudinit_disk.init.name
}

output "cloudinit_path" {
  description = "Path of the created libvirt cloudinit disk"
  value       = libvirt_cloudinit_disk.init.path
}
