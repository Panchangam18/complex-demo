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
      
      # Wait for Helm installation to complete (direct deployment)
      echo "Installing Prometheus stack directly via Helm..."
      helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
      helm repo update
      
      # Install prometheus stack with public access
      helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
        -n observability \
        --set fullnameOverride=prometheus \
        --set prometheus.prometheusSpec.replicas=1 \
        --set prometheus.prometheusSpec.retention=2h \
        --set prometheus.prometheusSpec.storageSpec={} \
        --set grafana.enabled=true \
        --set grafana.replicas=1 \
        --set grafana.adminPassword=admin123 \
        --set grafana.persistence.enabled=false \
        --set grafana.service.type=LoadBalancer \
        --set grafana.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="classic" \
        --set alertmanager.alertmanagerSpec.replicas=1 \
        --set alertmanager.alertmanagerSpec.storage={} \
        --set nodeExporter.enabled=true \
        --set kubeStateMetrics.enabled=true \
        --set defaultRules.create=true \
        --wait --timeout=600s
        
      echo "Observability stack deployed successfully!"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Clean up Helm releases
      helm uninstall prometheus-stack -n observability --ignore-not-found=true || true
      
      # Clean up namespaces
      kubectl delete namespace argocd --ignore-not-found=true
      kubectl delete namespace observability --ignore-not-found=true
      
      # Clean up any remaining CRDs
      kubectl delete crd -l app.kubernetes.io/name=kube-prometheus-stack --ignore-not-found=true || true
    EOT
  }
}

# Get ArgoCD URL and credentials
data "external" "argocd_info" {
  program = ["bash", "-c", <<-EOT
    # Update kubeconfig first
    aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name} --profile ${var.aws_profile} > /dev/null 2>&1
    
    # Get ArgoCD URL
    ARGOCD_URL=""
    for i in {1..30}; do
      ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
      if [ ! -z "$ARGOCD_URL" ]; then
        break
      fi
      sleep 10
    done
    
    # Get ArgoCD admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    
    # Get Grafana URL
    GRAFANA_URL=""
    for i in {1..30}; do
      GRAFANA_URL=$(kubectl get svc prometheus-stack-grafana -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
      if [ ! -z "$GRAFANA_URL" ]; then
        break
      fi
      sleep 10
    done
    
    # Get Prometheus URL (internal)
    PROMETHEUS_URL="prometheus-prometheus.observability.svc.cluster.local:9090"
    
    echo "{\"argocd_url\":\"$ARGOCD_URL\",\"argocd_password\":\"$ARGOCD_PASSWORD\",\"grafana_url\":\"$GRAFANA_URL\",\"prometheus_url\":\"$PROMETHEUS_URL\"}"
  EOT
  ]
  
  depends_on = [null_resource.argocd_install]
} 