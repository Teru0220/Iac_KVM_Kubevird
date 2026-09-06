resource "libvirt_cloudinit_disk" "init" {
  name      = var.node.cloudinit_name
  user_data = templatefile("${path.module}/user-data.yaml", {
    ssh_public_key = var.ssh_public_key
  })
  meta_data = yamlencode({
    instance-id    = var.node.instance_id
    local-hostname = var.node.hostname
  })
}