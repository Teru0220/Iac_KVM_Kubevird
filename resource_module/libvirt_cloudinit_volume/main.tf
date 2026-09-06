resource "libvirt_volume" "cloudinit" {
  name   = var.cloudinit_name
  pool   = var.volume_pool

  target = {
    format = {
      type = "raw"
    }
  }

  create = {
    content = {
      url = var.cloudinit_path
    }
  }
}