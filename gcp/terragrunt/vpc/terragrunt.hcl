include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../terraform/modules/vpc"
}

inputs = {
  project_id   = "mediapulse-513322"
  region       = "europe-west1"
  network_name = "mediapulse-vpc-dev"
}