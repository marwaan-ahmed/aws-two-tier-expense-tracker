# The state lives in the S3 bucket created by bootstrap/ (see its
# state_bucket_name output). Terraform doesn't allow variables in this block,
# so the name is written out. An AWS account ID isn't a secret.
terraform {
  backend "s3" {
    bucket       = "expense-tracker-tfstate-941167138759"
    key          = "terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true # S3-native locking (Terraform >= 1.10), no DynamoDB table
  }
}
