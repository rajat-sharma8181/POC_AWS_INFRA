output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority" {
  description = "Base64-encoded certificate authority data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "node_group_status" {
  description = "Status of the managed node group"
  value       = aws_eks_node_group.main.status
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "kubectl_config_command" {
  description = "Run this command to configure kubectl after deploy"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "cloudwatch_agent_role_arn" {
  description = "IRSA role ARN for the CloudWatch agent"
  value       = aws_iam_role.cloudwatch_agent.arn
}

output "cloudwatch_addon_version" {
  description = "Resolved version of the amazon-cloudwatch-observability EKS add-on"
  value       = aws_eks_addon.cloudwatch_observability.addon_version
}
