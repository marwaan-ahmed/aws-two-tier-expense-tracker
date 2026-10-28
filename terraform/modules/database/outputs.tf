output "address" {
  value = aws_db_instance.main.address
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "secret_arn" {
  value = aws_db_instance.main.master_user_secret[0].secret_arn
}
