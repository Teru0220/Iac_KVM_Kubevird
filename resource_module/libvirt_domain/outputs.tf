output "domain_name" {
  description = "Name of the created libvirt domain"
  value       = libvirt_domain.domain.name
}

output "ip_address" {
  description = "The assigned IPv4 address extracted via Data Source"
  value = try(
    # 最初のインターフェースの最初の IPv4 アドレスを取得
    one(flatten([for interface in data.libvirt_domain_interface_addresses.this.interfaces : [for addr in interface.addrs : addr.addr if addr.type == "ipv4" && addr.addr != "127.0.0.1"]])),
    ""
  )
}