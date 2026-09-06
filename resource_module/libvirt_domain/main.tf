resource "libvirt_domain" "domain" {
  name        = var.node.domain_name
  memory      = var.node.domain_memory
  memory_unit = var.node.domain_memory_unit
  vcpu        = var.node.domain_vcpu
  type        = var.node.domain_type

  os = var.node.os

  cpu = var.node.cpu

  features = var.node.features

  devices = merge(var.node.devices, {
    disks = [
      {
        source = {
          volume = {
            pool   = var.node.volume_pool
            volume = var.volume_name
          }
        }
        driver = var.node.disk_driver
        target = var.node.disk_target
      },
      {
        source = {
          volume = {
            pool   = var.node.volume_pool
            volume = var.cloudinit_volume_name
          }
        }
        target = {
          dev = "vdb"
          bus = "virtio"
        }
      }
    ]
  })
}