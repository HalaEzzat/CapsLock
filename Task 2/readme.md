# Task 2: Terraform Module for Kubernetes Deployment

## Module Structure:
```sh
.
├── main.tf
├── variables.tf
└── outputs.tf
```
## Example Usage Block
```hcl
# main.tf in your root configuration directory

# Configure the Kubernetes provider
# Ensure your kubectl is configured to connect to your Kubernetes cluster
# or provide explicit kubeconfig details here.
provider "kubernetes" {
  # Example: If you have a kubeconfig file at a non-standard path
  # config_path = "~/.kube/config"
}

# Call the PHP-FPM Kubernetes module
module "my_php_fpm_app_deployment" {
  source = "./php-fpm-k8s-module" # Path to your module directory

  app_name       = "my-symfony-web-app"
  replicas       = 2
  image          = "php:8.1-fpm-alpine" # Replace with your actual application image
  container_port = 9000 # Standard PHP-FPM port
  namespace      = "default" # Or your desired namespace

  env_vars = {
    APP_ENV    = "production"
    DATABASE_URL = "mysql://user:password@mysql-service:3306/mydb"
    SYMFONY_DEBUG = "0"
  }

  cpu_request    = "150m"
  memory_request = "256Mi"
  cpu_limit      = "300m"
  memory_limit   = "512Mi"
}

# Output the service IP for easy access
output "app_service_ip" {
  value = module.my_php_fpm_app_deployment.service_cluster_ip
}

output "app_deployment_name" {
  value = module.my_php_fpm_app_deployment.deployment_name
}

```
---
## How to Apply and Use the Module
1. Save the Module Files:
   - Create a directory, for example, `php-fpm-k8s-module`.
   - Save `main.tf`, `variables.tf`, and `outputs.tf` inside this directory.
2. Create Your Root Configuration:
   - Create a separate directory for your application's Terraform configuration, e.g., `example-app`.
   - Inside `example-app`, create a `main.tf` file and paste the `Example Usage Block` content into it.
3. Ensure Kubernetes Context:
   - Make sure your `kubectl` is configured and pointing to the correct Kubernetes cluster.
   - Terraform's Kubernetes provider uses your local `kubeconfig` by default.
   - You can test this by running `kubectl get nodes`.
4. Initialize Terraform:
   - Navigate to your example-app directory in your terminal.
   - Run `terraform init`. This command downloads the necessary providers (like kubernetes) and initializes the module.
5. Plan the Deployment:
   - Run `terraform plan`. This command shows you what Terraform will do (i.e., create a Kubernetes Deployment and Service) without actually making any changes to your cluster. Review the plan carefully.
6. Apply the Configuration:
   - Run `terraform apply`. If the plan looks correct, type yes when prompted to proceed with the deployment.
7. Verify Deployment:
   - After `terraform apply` completes, you can verify the resources in your Kubernetes cluster:
   - - Check the Deployment: kubectl get deployment my-symfony-web-app
     - Check the Pods: kubectl get pods -l app=my-symfony-web-app
     - Check the Service: kubectl get service my-symfony-web-app-service
8. Access the Service:
   - The `service_cluster_ip` output will show the `internal IP address` of your service within the cluster.
   - You can access this from other pods within the same Kubernetes cluster.
   - To access it from outside the cluster, you would typically need to expose it further using an Ingress, NodePort, or LoadBalancer Service (which are beyond the scope of this module, but common next steps).