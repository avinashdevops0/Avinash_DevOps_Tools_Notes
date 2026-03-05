module "ec2_instance" {
  source = "../modules/ec2"

  instance_name = var.instance_conf.instance_name
  instance_type = var.instance_conf.instance_type
  image_id        = var.instance_conf.image_id
  key_name      = var.instance_conf.key_name
  tags          = var.instance_conf.tags
}