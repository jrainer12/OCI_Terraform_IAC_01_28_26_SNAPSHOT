############################################
# Input variables
############################################

variable "compartment_ocid" {
  description = "OCID of the compartment where OKE and networking will be created"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "OCI region name (e.g., us-ashburn-1)"
  type        = string
}

variable "region_identifier" {
  description = "Short region key (e.g., IAD for us-ashburn-1)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the OKE cluster (e.g., v1.34.1)"
  type        = string
}

variable "image_id" {
  description = "Worker image OCID (required if create_node_pool=true). Find the latest aarch64 image for your Kubernetes version at: https://docs.oracle.com/en-us/iaas/images/"
  type        = string
  sensitive   = true
  default     = ""
}

variable "create_node_pool" {
  description = "Whether to create the node pool (set to false to skip node pool creation)"
  type        = bool
  default     = true
}
