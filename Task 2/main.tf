# main.tf

resource "kubernetes_deployment_v1" "php_fpm_app" {
  # Metadata for the Deployment
  metadata {
    name      = var.app_name
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }

  # Specification for the Deployment
  spec {
    replicas = var.replicas
    selector {
      match_labels = {
        app = var.app_name
      }
    }
    template {
      metadata {
        labels = {
          app = var.app_name
        }
      }
      spec {
        container {
          name  = var.app_name
          image = var.image
          port {
            container_port = var.container_port
          }

          # Resource requests and limits for the container
          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }

          # Environment variables (optional)
          dynamic "env" {
            for_each = var.env_vars
            content {
              name  = env.key
              value = env.value
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "php_fpm_service" {
  # Metadata for the Service
  metadata {
    name      = "${var.app_name}-service" # Name the service distinctly
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }

  # Specification for the Service
  spec {
    selector = {
      app = kubernetes_deployment_v1.php_fpm_app.metadata[0].labels.app # Selects pods created by the deployment
    }
    port {
      port        = var.container_port # Service port
      target_port = var.container_port # Target container port
      protocol    = "TCP"
    }
    type = "ClusterIP" # Expose internally within the cluster
  }
}
