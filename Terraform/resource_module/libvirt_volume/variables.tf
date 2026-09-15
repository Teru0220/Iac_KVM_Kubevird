variable "node" {
  description = "Configuration for one node volume"
  type = object({
    domain_name     = string
    volume_name     = string
    image_path      = string
    volume_pool     = string
    volume_capacity = number
    volume_format   = string
    volume_target   = any
  })
}
