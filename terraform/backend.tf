# ============================================================
# IMPORTANT: Before running terraform init, update the values
# below with your actual S3 bucket and DynamoDB table names.
#
# To create these resources, run the commands in README.md
# under "Step 1: Create Remote Backend Resources".
# ============================================================
terraform {
  backend "s3" {
    bucket         = "REPLACE-WITH-YOUR-TERRAFORM-STATE-BUCKET"
    key            = "eks/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "REPLACE-WITH-YOUR-DYNAMODB-LOCK-TABLE"
  }
}
