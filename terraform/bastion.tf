# ── Ubuntu 22.04 LTS AMI (latest) ────────────────────────────────
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Key Pair ──────────────────────────────────────────────────────
resource "aws_key_pair" "bastion" {
  key_name   = "${local.cluster_name}-bastion-key"
  public_key = var.bastion_public_key
}

# ── Security Group ────────────────────────────────────────────────
resource "aws_security_group" "bastion" {
  name        = "${local.cluster_name}-bastion-sg"
  description = "Bastion host SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.cluster_name}-bastion-sg"
  }
}

# Allow bastion to reach EKS cluster API
resource "aws_security_group_rule" "bastion_to_cluster" {
  type                     = "ingress"
  description              = "Bastion to EKS API"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.eks_cluster.id
}

# Allow bastion to reach worker nodes
resource "aws_security_group_rule" "bastion_to_nodes" {
  type                     = "ingress"
  description              = "Bastion to worker nodes"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.eks_nodes.id
}

# ── Bastion EC2 Instance ──────────────────────────────────────────
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.public[0].id
  key_name               = aws_key_pair.bastion.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y unzip curl

    # AWS CLI v2
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip /tmp/awscliv2.zip -d /tmp && /tmp/aws/install

    # kubectl (matches EKS cluster version)
    curl -fsSL -o /usr/local/bin/kubectl \
      "https://s3.us-west-2.amazonaws.com/amazon-eks/${var.eks_cluster_version}/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl
  EOF

  tags = {
    Name = "${local.cluster_name}-bastion"
  }
}

# ── Elastic IP ────────────────────────────────────────────────────
resource "aws_eip" "bastion" {
  instance   = aws_instance.bastion.id
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${local.cluster_name}-bastion-eip"
  }
}
