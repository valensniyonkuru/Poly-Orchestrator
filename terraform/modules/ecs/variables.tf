variable "project"         { type = string }
variable "environment"     { type = string }
variable "vpc_id"          { type = string }
variable "public_subnets"  { type = list(string) }
variable "private_subnets" { type = list(string) }
variable "ecr_frontend"    { type = string }
variable "ecr_backend"     { type = string }
variable "db_password"     { type = string; sensitive = true }

output "cluster_name"  { value = aws_ecs_cluster.main.name }
output "cluster_arn"   { value = aws_ecs_cluster.main.arn }
output "alb_dns_name"  { value = aws_lb.main.dns_name }
output "alb_arn"       { value = aws_lb.main.arn }
