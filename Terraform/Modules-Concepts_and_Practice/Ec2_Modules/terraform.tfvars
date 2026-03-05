instance_conf = {
  instance_name = "my-ec2"
  instance_type = "t3.micro"
  image_id      = "ami-0c02fb55956c7d316"
  key_name      = "my-keypair"

  tags = {
    Environment = "dev"
    Owner       = "me"
  }
}