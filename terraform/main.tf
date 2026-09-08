terraform {
  required_version = ">= 1.3.0"

  # Local state — no backend configuration needed for this demo.
  # Each pipeline run starts fresh; resources are created anew and
  # destroyed at end-of-life via the destroy workflow.

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.31.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Default VPC ──────────────────────────────────────────────────────────────
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ── SSH Key Pair ──────────────────────────────────────────────────────────────
resource "tls_private_key" "rke2" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "rke2" {
  key_name_prefix = "rke2-cluster-demo-"
  public_key      = tls_private_key.rke2.public_key_openssh
  tags            = { Name = "rke2-cluster-demo" }
}

# Write private key so Ansible can use it
resource "local_file" "private_key" {
  content         = tls_private_key.rke2.private_key_pem
  filename        = "${path.module}/../ansible/rke2-key.pem"
  file_permission = "0600"
}

# ── Security Groups ───────────────────────────────────────────────────────────

# ALB security group — accepts public HTTP/HTTPS
resource "aws_security_group" "alb" {
  name_prefix = "rke2-alb-sg-"
  description = "Allow HTTP/HTTPS inbound to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "rke2-alb-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# Node security group — inter-node + ALB + SSH
resource "aws_security_group" "nodes" {
  name_prefix = "rke2-nodes-sg-"
  description = "RKE2 cluster node security group"
  vpc_id      = data.aws_vpc.default.id

  # SSH from anywhere (Ansible needs this)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # RKE2 supervisor API (inter-node)
  ingress {
    description = "RKE2 supervisor"
    from_port   = 9345
    to_port     = 9345
    protocol    = "tcp"
    self        = true
  }

  # Kubernetes API (runner needs this for kubectl)
  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP NodePort — from ALB
  ingress {
    description     = "HTTP NodePort from ALB"
    from_port       = 30080
    to_port         = 30080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # HTTP/HTTPS between nodes
  ingress {
    description = "HTTP inter-node"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "HTTPS inter-node"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    self        = true
  }

  # VXLAN (Flannel/Canal overlay)
  ingress {
    description = "VXLAN overlay"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }

  # kubelet metrics
  ingress {
    description = "Kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "rke2-nodes-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# ── EC2 Instances ─────────────────────────────────────────────────────────────
resource "aws_instance" "server" {
  ami                         = var.ubuntu_ami
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.nodes.id]
  key_name                    = aws_key_pair.rke2.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "rke2-server" }
}

resource "aws_instance" "agent" {
  ami                         = var.ubuntu_ami
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.nodes.id]
  key_name                    = aws_key_pair.rke2.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "rke2-agent" }
}

# ── Application Load Balancer ─────────────────────────────────────────────────
resource "aws_lb" "rke2" {
  name_prefix        = "rke2-"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  tags = { Name = "rke2-cluster-alb" }
}

resource "aws_lb_target_group" "ingress" {
  name_prefix = "rke2-"
  port        = 30080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    path                = "/healthz"
    port                = "30080"
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
  }

  tags = { Name = "rke2-ingress-tg" }

  lifecycle {
    create_before_destroy = true
  }
}

# Register both nodes so ALB can reach either
resource "aws_lb_target_group_attachment" "server" {
  target_group_arn = aws_lb_target_group.ingress.arn
  target_id        = aws_instance.server.id
  port             = 30080
}

resource "aws_lb_target_group_attachment" "agent" {
  target_group_arn = aws_lb_target_group.ingress.arn
  target_id        = aws_instance.agent.id
  port             = 30080
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.rke2.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress.arn
  }
}
