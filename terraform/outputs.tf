output "app_url" {
  description = "Open this in your browser."
  value       = "http://${module.loadbalancer.dns_name}"
}

output "dashboard_url" {
  description = "The CloudWatch dashboard."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${module.monitoring.dashboard_name}"
}
