resource "libvirt_cloudinit_disk" "init" {
  name = var.node.cloudinit_name
  user_data = join("", [
    templatefile("${path.module}/user-data.yml", {
      ssh_public_key = var.ssh_public_key
      cloudinit_user = var.cloudinit_user
    }),
    var.user_password == "" ? "\nssh_pwauth: false\n" : "\nchpasswd:\n  expire: false\n  list: |\n    ${var.cloudinit_user}:${var.user_password}\nssh_pwauth: true\n"
  ])
  meta_data = yamlencode({
    instance-id    = var.node.instance_id
    local-hostname = var.node.hostname
  })
}