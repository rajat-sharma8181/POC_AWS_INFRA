# ── EKS OIDC Provider ────────────────────────────────────────────
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

locals {
  oidc_issuer = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

# ── CloudWatch Log Groups ─────────────────────────────────────────
# Both groups are created before cluster logging is enabled.
# eks.tf depends_on aws_cloudwatch_log_group.eks_cluster to enforce ordering
# so AWS uses this group (with our 7-day retention) instead of defaulting to Never Expire.
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.control_plane_log_retention_days

  tags = {
    Name = "/aws/eks/${local.cluster_name}/cluster"
  }
}

resource "aws_cloudwatch_log_group" "container_insights" {
  name              = "/aws/containerinsights/${local.cluster_name}/performance"
  retention_in_days = var.container_insights_log_retention_days

  tags = {
    Name = "/aws/containerinsights/${local.cluster_name}/performance"
  }
}

# ── IRSA Role for CloudWatch Agent ───────────────────────────────
resource "aws_iam_role" "cloudwatch_agent" {
  name = "${local.cluster_name}-cloudwatch-agent"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_agent.name
}

# ── EKS Add-on: amazon-cloudwatch-observability ──────────────────
# containerLogs.enabled = false  → no Fluent Bit pod log shipping (cost saving)
# enhanced_container_insights = false → ~15 metrics instead of hundreds (cost saving)
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "amazon-cloudwatch-observability"
  service_account_role_arn = aws_iam_role.cloudwatch_agent.arn

  configuration_values = jsonencode({
    containerLogs = {
      enabled = false
    }
    agent = {
      config = {
        logs = {
          metrics_collected = {
            kubernetes = {
              enhanced_container_insights = false
            }
          }
        }
      }
    }
  })

  depends_on = [
    aws_cloudwatch_log_group.eks_cluster,
    aws_cloudwatch_log_group.container_insights,
    aws_iam_role_policy_attachment.cloudwatch_agent,
    aws_eks_node_group.main,
  ]
}
