# variables.tf

variable "app_name" {
  description = "The name of the application (used for Kubernetes resource names and labels)."
  type        = string
}

variable "replicas" {
  description = "The number of desired replicas for the Kubernetes Deployment."
  type        = number
  default     = 1 # Sensible default
}

variable "image" {
  description = "The Docker image to use for the PHP-FPM container (e.g., 'my-registry/my-php-fpm-app:1.0.0')."
  type        = string
}

variable "container_port" {
  description = "The port on which the PHP-FPM container listens (e.g., 9000 for PHP-FPM)."
  type        = number
}

variable "env_vars" {
  description = "An optional map of environment variables to pass to the container."
  type        = map(string)
  default     = {} # Empty map by default
}

variable "namespace" {
  description = "The Kubernetes namespace to deploy the resources into."
  type        = string
  default     = "default" # Deploy to default namespace if not specified
}

variable "cpu_request" {
  description = "The amount of CPU to request for the container (e.g., '100m' for 0.1 CPU)."
  type        = string
  default     = "100m"
}

variable "memory_request" {
  description = "The amount of memory to request for the container (e.g., '128Mi')."
  type        = string
  default     = "128Mi"
}

variable "cpu_limit" {
  description = "The maximum amount of CPU the container can use (e.g., '200m')."
  type        = string
  default     = "200m"
}

variable "memory_limit" {
  description = "The maximum amount of memory the container can use (e.g., '256Mi')."
  type        = string
  default     = "256Mi"
}
