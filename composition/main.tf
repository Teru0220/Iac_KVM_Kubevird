module "infrastructure" {
  source = "../infrastructure_module"
  for_each = {
    for node in var.nodes : node.domain_name => node
  }

  node           = each.value
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))
  cloudinit_user = var.cloudinit_user
  user_password  = var.user_password
}

# Ansibleインベントリファイルの動的生成
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.yml"
  content  = templatefile("${path.module}/../ansible/inventory.yml.tftpl", {
    nodes = [
      for key, instance in module.infrastructure : {
        name = instance.domain_name != null ? instance.domain_name : key
        ip   = instance.ip_address != null ? instance.ip_address : ""
        role = instance.role != null ? instance.role : ""
      }
    ]
  })
}
