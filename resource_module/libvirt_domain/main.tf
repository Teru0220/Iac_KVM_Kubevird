resource "libvirt_domain" "domain" {
  name        = var.node.domain_name
  memory      = var.node.domain_memory
  memory_unit = var.node.domain_memory_unit
  vcpu        = var.node.domain_vcpu
  type        = var.node.domain_type
  running = true

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
    # ネットワークインターフェースの設定
    interfaces = [
      {
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = "default"
          }
        }
        # IP アドレス取得待機の設定
        wait_for_ip = {
          network = "0.0.0.0/0" # 任意の IPv4 アドレスが割り当てられるまで待機
          source  = "lease"     # DHCP リースから取得（または "agent" / "any"）
          timeout = 300         # タイムアウト時間（秒）
        }
      }
    ]
  })
}

# 起動したドメインから IP アドレス情報を取得する Data Source
data "libvirt_domain_interface_addresses" "this" {
  domain = libvirt_domain.domain.name
  source = "lease" # DHCP リースから取得する場合（qemu-guest-agent を使うなら "agent"）

  depends_on = [
    libvirt_domain.domain
  ]
}