output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.rke2.dns_name
}

output "server_public_ip" {
  description = "Public IP of the RKE2 server node"
  value       = aws_instance.server.public_ip
}

output "agent_public_ip" {
  description = "Public IP of the RKE2 agent node"
  value       = aws_instance.agent.public_ip
}

output "server_private_ip" {
  description = "Private IP of the RKE2 server node (used by agent config)"
  value       = aws_instance.server.private_ip
}

output "private_key_pem" {
  description = "Private key for SSH access (sensitive)"
  value       = tls_private_key.rke2.private_key_pem
  sensitive   = true
}
