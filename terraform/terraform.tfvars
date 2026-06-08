aws_region   = "ap-south-1"
project_name = "eks-demo"
environment  = "dev"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

eks_cluster_version = "1.32"
node_instance_type  = "t3.small"
node_desired_size   = 2
node_min_size       = 2
node_max_size       = 3
