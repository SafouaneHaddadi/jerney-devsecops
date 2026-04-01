# ------------------------------
# ArgoCD GitOps Deployment
# ------------------------

# create the ArgoCD namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# install ArgoCD using Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.8.6"

  # set the service to LoadBalancer (accessible from outside)
  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  # wait for the EKS cluster to be ready
  depends_on = [
    module.eks
  ]
}

resource "null_resource" "wait_for_argocd_crd" {
  depends_on = [helm_release.argocd]

  triggers = {
    helm_version = helm_release.argocd.version
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for ArgoCD CRD..."
      for i in {1..60}; do
        if kubectl get crd applications.argoproj.io > /dev/null 2>&1; then
          echo "ArgoCD CRD is ready!"
          exit 0
        fi
        echo "Attempt $i/60: CRD not ready yet, waiting 5 seconds..."
        sleep 5
      done
      echo "ERROR: ArgoCD CRD not ready after 5 minutes"
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# define the ArgoCD application 
resource "kubernetes_manifest" "argocd_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "jerney-blog"
      namespace = "argocd"
      labels = {
        "app.kubernetes.io/part-of" = "jerney"
      }
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/SafouaneHaddadi/jerney-devsecops"
        targetRevision = "main"
        path           = "k8s"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "jerney"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
          "ApplyOutOfSyncOnly=true"
        ]
      }
    }
  }

  depends_on = [
    null_resource.wait_for_argocd_crd
    ]
}
