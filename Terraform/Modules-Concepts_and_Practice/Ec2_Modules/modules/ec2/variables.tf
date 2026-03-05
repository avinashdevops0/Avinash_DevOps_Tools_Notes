variable "instance_conf" {
  description = "Instance configuration"

  type = object({
    instance_name = string
    instance_type = string
    image_id      = string
    key_name      = string
    tags          = map(string)
  })
}