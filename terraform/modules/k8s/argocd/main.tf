resource "null_resource" "argocd_install" {
  triggers = {
    cluster_endpoint = var.cluster_endpoint
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Update kubeconfig
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name} --profile ${var.aws_profile}
      
      # Create namespace
      kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
      
      # Install ArgoCD
      kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
      
      # Wait for ArgoCD to be ready
      kubectl -n argocd wait --for=condition=available --timeout=600s deployment/argocd-server
      
      # Configure ArgoCD server for insecure mode (allows HTTP access)
      IMAGE=$(kubectl -n argocd get deployment argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}')
      kubectl -n argocd patch deployment argocd-server --type='merge' -p='{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","image":"'$IMAGE'","command":["argocd-server","--insecure"]}]}}}}'
      
      # Wait for the patched deployment to be ready
      kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-server
      
      # Expose via LoadBalancer with proper AWS annotations
      kubectl -n argocd patch svc argocd-server -p '{"spec": {"type": "LoadBalancer"}}'
      kubectl -n argocd annotate svc argocd-server service.beta.kubernetes.io/aws-load-balancer-healthcheck-path="/healthz" --overwrite
      kubectl -n argocd annotate svc argocd-server service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval="10" --overwrite
      kubectl -n argocd annotate svc argocd-server service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold="2" --overwrite
      kubectl -n argocd annotate svc argocd-server service.beta.kubernetes.io/aws-load-balancer-backend-protocol="http" --overwrite
      
      # Apply the GitOps bootstrap applications
      kubectl apply -f ${var.k8s_manifests_path}/envs/dev/applications.yaml
      
      # Wait a moment for ArgoCD to process the applications
      sleep 30
      
      # Apply observability stack for automatic deployment
      kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
      kubectl apply -f ${var.k8s_manifests_path}/envs/dev/aws/observability/prometheus-lite.yaml
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      kubectl delete namespace argocd --ignore-not-found=true
      kubectl delete namespace observability --ignore-not-found=true
    EOT
  }
} 