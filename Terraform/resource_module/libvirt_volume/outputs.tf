output "volume_name" {
  description = "Name of the created libvirt volume"
  value       = libvirt_volume.node_disk.name
}
