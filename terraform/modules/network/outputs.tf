output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "app_subnet_ids" {
  value = [aws_subnet.app_a.id, aws_subnet.app_b.id]
}

output "data_subnet_ids" {
  value = [aws_subnet.data_a.id, aws_subnet.data_b.id]
}
