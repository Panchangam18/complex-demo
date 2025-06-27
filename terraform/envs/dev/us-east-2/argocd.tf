module "argocd" {
  source = "../../../modules/k8s/argocd"

  cluster_name        = module.aws_eks.cluster_id
  cluster_endpoint    = module.aws_eks.cluster_endpoint
  region              = var.aws_region
  aws_profile         = var.aws_profile
  k8s_manifests_path  = "../../../k8s"

  # Ensure EKS cluster is ready first
  depends_on = [module.aws_eks]
} 