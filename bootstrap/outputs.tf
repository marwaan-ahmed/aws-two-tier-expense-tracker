output "state_bucket_name" {
  description = "S3 bucket that holds the main stack's Terraform state (used in terraform/backend.tf)."
  value       = aws_s3_bucket.state.bucket
}
