module "cloudinit" {
  source = "../resource_module/libvirt_cloudinit_disk"

  node           = var.node
  ssh_public_key = var.ssh_public_key
  cloudinit_user = var.cloudinit_user
  user_password  = var.user_password
}

module "volume" {
  source = "../resource_module/libvirt_volume"

  node = var.node
}

module "cloudinit_volume" {
  source = "../resource_module/libvirt_cloudinit_volume"

  cloudinit_name = var.node.cloudinit_name
  cloudinit_path = module.cloudinit.cloudinit_path
  volume_pool    = var.node.volume_pool
}

module "domain" {
  source = "../resource_module/libvirt_domain"

  node                 = var.node
  volume_name          = module.volume.volume_name
  cloudinit_volume_name = module.cloudinit_volume.volume_name
}
