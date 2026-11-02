include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../terraform/modules/gke"
}

dependency "vpc" {
  config_path = "../vpc"
  
  mock_outputs = {
    network_name    = "mock-vpc"
    subnetwork_name = "mock-subnet"
  }
}

inputs = {
  project_id      = "mediapulse-513322"
  region          = "europe-west1"
  cluster_name    = "mediapulse-gke-dev"
  network_name    = dependency.vpc.outputs.network_name
  subnetwork_name = dependency.vpc.outputs.subnetwork_name
  
  machine_type = "e2-standard-2"
  node_count   = 3
  disk_size_gb = 30
}