output "application_access_url" {
  description = "Entry URL to access application"
  value = var.enable_alb ? "http://${aws_lb.prod_alb[0].dns_name}" : "http://${aws_instance.web_server[0].public_ip}"
}

output "individual_instance_ips" {
  description = "Direct Instance Public IPs for debugging/testing"
  value       = [for inst in aws_instance.web_server : inst.public_ip]
}