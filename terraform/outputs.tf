output "vpc_id" {
  value = module.network.vpc_id
}

output "app_url" {
  description = "Open this in your browser."
  value       = "http://${module.loadbalancer.dns_name}"
}

output "asg_name" {
  description = "The Auto Scaling group, for the 'terminate a server' test."
  value       = module.compute.asg_name
}
