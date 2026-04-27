variable "project"         { type = string }
variable "environment"     { type = string }
variable "vpc_id"          { type = string }
variable "private_subnets" { type = list(string) }
variable "public_subnets"  { type = list(string) }
variable "k8s_version"     { type = string; default = "1.29" }

output "cluster_name"      { value = aws_eks_cluster.main.name }
output "cluster_endpoint"  { value = aws_eks_cluster.main.endpoint; sensitive = true }
output "cluster_ca"        { value = aws_eks_cluster.main.certificate_authority[0].data; sensitive = true }
output "node_group_name"   { value = aws_eks_node_group.main.node_group_name }
