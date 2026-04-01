output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "configure_kubectl_command" {
  description = "Run this to connect kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ArgoCD outputs
data "kubernetes_secret" "argocd_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

output "argocd_admin_password" {
  description = "ArgoCD admin password (base64 encoded)"
  value       = data.kubernetes_secret.argocd_admin.data["password"]
  sensitive   = true
}

data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

output "argocd_server_url" {
  description = "ArgoCD server URL (LoadBalancer)"
  value       = "https://${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname}"
}