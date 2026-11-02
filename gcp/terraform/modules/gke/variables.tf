variable "project_id" { type = string }
variable "region" { type = string }
variable "cluster_name" { type = string }
variable "network_name" { type = string }
variable "subnetwork_name" { type = string }

variable "machine_type" {
  description = "Machine type for GKE node pool (defines CPU + RAM)"
  type        = string
  default     = "e2-standard-2"
}

variable "node_count" {
  description = "Number of worker nodes per zone in the pool"
  type        = number
  default     = 1
}

variable "disk_size_gb" {
  description = "Disk size for worker nodes in GB"
  type        = number
  default     = 30
}