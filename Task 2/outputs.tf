# outputs.tf

output "deployment_name" {
  description = "The name of the Kubernetes Deployment."
  value       = kubernetes_deployment_v1.php_fpm_app.metadata[0].name
}

output "service_name" {
  description = "The name of the Kubernetes Service."
  value       = kubernetes_service_v1.php_fpm_service.metadata[0].name
}

output "service_cluster_ip" {
  description = "The ClusterIP of the Kubernetes Service."
  value       = kubernetes_service_v1.php_fpm_service.spec[0].cluster_ip
}
