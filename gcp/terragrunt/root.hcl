remote_state {
  backend = "gcs"
  config = {
    bucket   = "mediapulse-tf-state-mediapulse-513322" 
    prefix   = "${path_relative_to_include()}/terraform.tfstate"
    project  = "mediapulse-513322"
    location = "europe-west1"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "google" {
  project = "mediapulse-513322"
  region  = "europe-west1"
}
EOF
}