resource "aws_instance" "this" {
  ami           = var.instance_conf.image_id
  instance_type = var.instance_conf.instance_type
  key_name      = var.instance_conf.key_name

  tags = merge(
    var.instance_conf.tags,
    {
      Name = var.instance_conf.instance_name
    }
  )
}