output "volume_name" {
  description = "Name of the cloud-init volume"
  value       = libvirt_volume.cloudinit.name
}