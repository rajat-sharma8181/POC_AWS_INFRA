# Basic EKS Infrastructure — Terraform + GitHub Actions

A beginner-friendly, minimal-cost Amazon EKS cluster in `ap-south-1` provisioned with Terraform and automated through a GitHub Actions CI/CD pipeline.

---

## Architecture Overview

```
                        ┌─────────────────────────────────────────────┐
                        │              AWS ap-south-1                  │
                        │                                              │
                        │  ┌──────────────────────────────────────┐   │
                        │  │           VPC 10.0.0.0/16             │   │
                        │  │                                       │   │
                        │  │  ┌─────────────┐  ┌───────────────┐  │   │
                        │  │  │ Public AZ-a  │  │ Public AZ-b   │  │   │
                        │  │  │ 10.0.1.0/24 │  │ 10.0.2.0/24  │  │   │
                        │  │  │  NAT GW  ◄──┼──┼──────────     │  │   │
                        │  │  └──────┬──────┘  └───────────────┘  │   │
                        │  │         │ IGW                         │   │
                        │  │  ┌──────▼──────┐  ┌───────────────┐  │   │
                        │  │  │ Private AZ-a│  │ Private AZ-b  │  │   │
                        │  │  │10.0.10.0/24 │  │ 10.0.20.0/24 │  │   │
                        │  │  │  Worker     │  │  Worker       │  │   │
                        │  │  │  Node(s)    │  │  Node(s)      │  │   │
                        │  │  └─────────────┘  └───────────────┘  │   │
                        │  │                                       │   │
                        │  │  ┌────────────────────────────────┐   │   │
                        │  │  │       EKS Control Plane        │   │   │
                        │  │  │    (managed by AWS, private     │   │   │
                        │  │  │     + public endpoint)         │   │   │
                        │  │  └────────────────────────────────┘   │   │
                        │  └──────────────────────────────────────┘   │
                        └─────────────────────────────────────────────┘
```

---

## Project Structure

```
basic-eks-infra/
├── .github/
│   └── workflows/
│       └── terraform.yml        # CI/CD pipeline
├── terraform/
│   ├── backend.tf               # S3 remote state + DynamoDB lock
│   ├── provider.tf              # AWS provider config
│   ├── versions.tf              # Terraform + provider version constraints
│   ├── variables.tf             # Input variable declarations
│   ├── terraform.tfvars         # Variable values (safe to commit)
│   ├── main.tf                  # Data sources + local values
│   ├── vpc.tf                   # VPC, subnets, IGW, NAT, route tables
│   ├── eks.tf                   # EKS cluster, node group, IAM, SGs
│   └── outputs.tf               # Output values
├── k8s/
│   ├── nginx-deployment.yaml    # Sample nginx Deployment
│   └── nginx-service.yaml       # LoadBalancer Service
├── .gitignore
└── README.md
```

---

## Prerequisites

Install the following tools before you begin.

### 1. AWS CLI

```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Windows (PowerShell)
winget install Amazon.AWSCLI

# Verify
aws --version
```

### 2. Terraform

```bash
# macOS / Linux (via tfenv — recommended)
brew install tfenv
tfenv install 1.7.5
tfenv use 1.7.5

# Windows
winget install Hashicorp.Terraform

# Verify
terraform version
```

### 3. kubectl

```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Windows
winget install Kubernetes.kubectl

# Verify
kubectl version --client
```

### 4. Configure AWS CLI

```bash
aws configure
# Enter:
#   AWS Access Key ID:     <your-access-key>
#   AWS Secret Access Key: <your-secret-key>
#   Default region:        ap-south-1
#   Default output format: json

# Verify
aws sts get-caller-identity
```

---

## Deployment Guide (Step by Step)

### Step 1 — Create Remote Backend Resources

These two resources must exist **before** running `terraform init`.

```bash
# Choose a globally unique bucket name
BUCKET_NAME="my-eks-tfstate-$(aws sts get-caller-identity --query Account --output text)"
TABLE_NAME="terraform-state-lock"
REGION="ap-south-1"

# Create S3 bucket
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

# Enable versioning (protects against accidental state deletion)
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Block all public access
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name "$TABLE_NAME" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo "Bucket: $BUCKET_NAME"
echo "Table:  $TABLE_NAME"
```

### Step 2 — Update backend.tf

Open [terraform/backend.tf](terraform/backend.tf) and replace the placeholders:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-eks-tfstate-123456789012"   # <-- your bucket
    key            = "eks/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"           # <-- your table
  }
}
```

### Step 3 — Initialise Terraform

```bash
cd terraform
terraform init
```

Expected output: `Terraform has been successfully initialized!`

### Step 4 — Review the Plan

```bash
terraform plan
```

This shows every resource Terraform will create — review it carefully before applying.

### Step 5 — Apply

```bash
terraform apply
# Type 'yes' when prompted
```

EKS provisioning takes **10–15 minutes**. Go grab a coffee.

### Step 6 — Configure kubectl

```bash
# Copy the exact command from Terraform outputs
aws eks update-kubeconfig --region ap-south-1 --name eks-demo-dev

# Verify connection
kubectl get nodes
kubectl get pods -A
```

---

## Deploy the Sample nginx Application

```bash
# Apply manifests
kubectl apply -f k8s/nginx-deployment.yaml
kubectl apply -f k8s/nginx-service.yaml

# Watch pods come up
kubectl get pods -w

# Get the LoadBalancer external IP / hostname (takes ~2 min)
kubectl get service nginx-service

# Test (replace <EXTERNAL-IP> with the value from above)
curl http://<EXTERNAL-IP>
```

---

## Terraform Commands Reference

| Command | Description |
|---------|-------------|
| `terraform init` | Download providers and configure backend |
| `terraform fmt` | Format all `.tf` files |
| `terraform validate` | Check syntax and configuration |
| `terraform plan` | Preview changes (dry run) |
| `terraform apply` | Create / update infrastructure |
| `terraform destroy` | Destroy all resources |
| `terraform output` | Print output values |
| `terraform state list` | List managed resources |

---

## GitHub Actions CI/CD Pipeline

### Required GitHub Secrets

Go to **GitHub → Your Repo → Settings → Secrets and variables → Actions → New repository secret**.

| Secret Name | Value | Notes |
|-------------|-------|-------|
| `AWS_ACCESS_KEY_ID` | Your IAM access key ID | Create an IAM user with least-privilege |
| `AWS_SECRET_ACCESS_KEY` | Your IAM secret access key | Never commit this value |

> **Tip — Least privilege IAM policy for the CI user:**
> The CI user needs permissions for EC2, EKS, IAM, VPC, S3, and DynamoDB.
> For learning, `AdministratorAccess` works; for production, scope it down.

### Pipeline Behaviour

| Event | Jobs that run |
|-------|--------------|
| Push to **any branch** (terraform files changed) | fmt → validate → plan |
| Push to **main** | fmt → validate → plan → **apply** (requires environment approval) |
| Pull Request to main | fmt → validate → plan (result posted as PR comment) |
| Manual `workflow_dispatch` — `apply` | fmt → validate → plan → **apply** |
| Manual `workflow_dispatch` — `destroy` | **destroy** |

### Setting Up Manual Approval (Optional but Recommended)

The `terraform-apply` and `terraform-destroy` jobs reference a GitHub Environment called `production`. To require human approval before they run:

1. Go to **Settings → Environments → New environment** → name it `production`
2. Enable **Required reviewers** → add yourself
3. Save

After this, every apply/destroy will pause and wait for your approval in the Actions UI.

---

## eksctl Alternative Commands

If you prefer `eksctl` over Terraform for quick experiments:

```bash
# Install eksctl
brew tap weaveworks/tap && brew install weaveworks/tap/eksctl   # macOS
# OR: https://eksctl.io/installation/

# Create cluster
eksctl create cluster \
  --name eks-demo-dev \
  --region ap-south-1 \
  --node-type t3.small \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3

# Delete cluster
eksctl delete cluster --name eks-demo-dev --region ap-south-1
```

---

## Estimated AWS Monthly Cost (ap-south-1)

> Prices as of 2025. Use the [AWS Pricing Calculator](https://calculator.aws) for up-to-date estimates.

| Resource | Qty | Unit price | Monthly |
|----------|-----|-----------|---------|
| EKS Control Plane | 1 | $0.10/hr | ~$72 |
| t3.small worker nodes | 2 | $0.023/hr | ~$34 |
| NAT Gateway | 1 | $0.045/hr + data | ~$33 |
| EBS (gp2 20 GB/node) | 2 | $0.10/GB/month | ~$4 |
| CloudWatch logs | — | varies | ~$3 |
| **Total estimate** | | | **~$146/month** |

### Cost-Saving Tips

- **Biggest saving**: Delete the cluster when not in use — the EKS control plane costs $0.10/hr even when idle.
- Lower `node_desired_size` to `1` in `terraform.tfvars` to save ~$17/month.
- Change `node_instance_type` to `t3.micro` (not recommended — EKS overhead can cause OOM).
- The NAT Gateway is required for private-subnet nodes. If you move nodes to public subnets (edit `eks.tf` → use `aws_subnet.public[*].id`), you save ~$33/month but lose the network isolation best practice.
- Run `terraform destroy` at the end of each session (see Cleanup section).

---

## Security Best Practices

- **No hardcoded credentials** — AWS keys live only in GitHub Secrets and local `~/.aws/credentials`.
- **Least-privilege IAM** — the EKS cluster role and node role attach only the AWS-managed policies they need.
- **Private worker nodes** — nodes sit in private subnets; only the NAT Gateway allows outbound internet.
- **Encrypted state** — S3 bucket uses AES-256 encryption; DynamoDB prevents concurrent state writes.
- **Public endpoint + private endpoint** — `kubectl` works from your laptop (public) and from within the VPC (private). For production, disable the public endpoint.
- **No SSH keys on nodes** — EKS managed node groups use SSM Session Manager for shell access; no inbound port 22.
- **`.gitignore` excludes** `*.tfstate`, `*.tfstate.backup`, and `*.auto.tfvars` — state files can contain secrets.

---

## Troubleshooting

### `terraform init` fails with NoSuchBucket

The S3 bucket in `backend.tf` does not exist. Complete Step 1 of the deployment guide first.

### `terraform apply` hangs at EKS cluster creation

Normal. EKS takes 10–15 minutes. Wait patiently or watch progress in the AWS Console under **EKS → Clusters**.

### `kubectl get nodes` shows `No resources found`

The node group may still be provisioning. Check:
```bash
aws eks describe-nodegroup \
  --cluster-name eks-demo-dev \
  --nodegroup-name eks-demo-dev-nodes \
  --region ap-south-1 \
  --query 'nodegroup.status'
```

### `error: You must be logged in to the server (Unauthorized)`

Your kubeconfig is stale or pointing at the wrong cluster. Re-run:
```bash
aws eks update-kubeconfig --region ap-south-1 --name eks-demo-dev
```

### LoadBalancer service stuck in `<pending>`

The AWS Load Balancer Controller is not required for basic LoadBalancer services — the in-tree controller handles them. Wait 2–3 minutes. If still pending:
```bash
kubectl describe service nginx-service
# Look for Events at the bottom for error messages
```

### GitHub Actions: `Error: credentials not found`

The `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` secret is missing or misspelled in repository Settings → Secrets.

### GitHub Actions: `fmt -check` fails

Run `terraform fmt -recursive` locally and commit the formatted files.

---

## Cleanup — Avoid Unexpected Charges

**Always clean up when done testing.**

### 1. Delete Kubernetes resources first

```bash
kubectl delete -f k8s/nginx-service.yaml    # deletes the AWS Load Balancer
kubectl delete -f k8s/nginx-deployment.yaml
```

> Wait ~2 minutes for the LoadBalancer to be deprovisioned by AWS before running destroy.
> If you skip this step, `terraform destroy` may hang because Terraform can't delete the VPC while the ELB exists.

### 2. Destroy Terraform infrastructure

```bash
cd terraform
terraform destroy
# Type 'yes' when prompted
```

### 3. Delete backend resources (optional)

```bash
# Empty and delete the S3 bucket
aws s3 rm s3://<YOUR-BUCKET-NAME> --recursive
aws s3api delete-bucket --bucket <YOUR-BUCKET-NAME> --region ap-south-1

# Delete the DynamoDB table
aws dynamodb delete-table --table-name terraform-state-lock --region ap-south-1
```

---

## Useful kubectl Commands

```bash
# Cluster info
kubectl cluster-info
kubectl get nodes -o wide

# Pods
kubectl get pods -A                         # all namespaces
kubectl describe pod <pod-name>
kubectl logs <pod-name>

# Services
kubectl get services

# Scale deployment
kubectl scale deployment nginx-deployment --replicas=3

# Execute into a pod
kubectl exec -it <pod-name> -- /bin/bash

# Apply / delete manifests
kubectl apply -f k8s/
kubectl delete -f k8s/
```

---

## Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub Actions — Terraform](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [eksctl Documentation](https://eksctl.io/)
