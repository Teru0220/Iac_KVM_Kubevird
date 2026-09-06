module "infrastructure" {
  source = "../infrastructure_module"
  for_each = {
    for node in var.nodes : node.domain_name => node
  }

  node           = each.value
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))
}
