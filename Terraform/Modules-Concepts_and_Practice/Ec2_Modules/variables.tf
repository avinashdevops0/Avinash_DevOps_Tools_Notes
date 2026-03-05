variable "instance_conf" {
  description = "Instance details"

  type = object({
    instance_name = string
    instance_type = string
    image_id      = string
    key_name      = string
    tags          = map(string)
  })
}