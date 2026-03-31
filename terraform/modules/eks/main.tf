module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  authentication_mode = "API"

  cluster_encryption_config = {
    resources = ["secrets"]
  }

  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  enable_cluster_creator_admin_permissions = true

  
}

# EBS CSI driver required for k8s to provision EBS volumes
resource "aws_eks_addon" "ebs_csi" {
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  depends_on = [module.eks]
}