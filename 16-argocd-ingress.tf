# ---- Argo CD Ingress and TLS ----
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = helm_release.argocd.namespace

    annotations = {
      "cert-manager.io/cluster-issuer"            = var.cluster_issuer_name
      "acme.cert-manager.io/http01-edit-in-place" = "true"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [var.argocd_hostname]
      secret_name = "argocd-server-tls"
    }

    rule {
      host = var.argocd_hostname

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-server"

              port {
                name = "http"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    helm_release.cluster_issuer,
  ]
}
