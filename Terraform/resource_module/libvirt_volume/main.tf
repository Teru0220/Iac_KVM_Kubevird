resource "libvirt_volume" "node_disk" {
  name     = var.node.volume_name
  pool     = var.node.volume_pool
  capacity = var.node.volume_capacity

  target = var.node.volume_target

  backing_store = {
    path = var.node.image_path
    format = {
      type = var.node.volume_format
    }
  }
}