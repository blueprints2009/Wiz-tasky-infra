resource "aws_instance" "bastion" {
  ami           = "ami-0c94855ba95c71c99" # Example Ubuntu 20.04 in us-east-1
  instance_type = "t3.micro"
  subnet_id     = module.vpc.public_subnets[0]
  key_name      = aws_key_pair.deployer.key_name

  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  associate_public_ip_address = true
}

resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "SSH access to Bastion"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_PUBLIC_IP/32"] # Restrict to your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
