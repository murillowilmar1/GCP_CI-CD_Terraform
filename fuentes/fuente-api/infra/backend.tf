terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }

  # bucket real se pasa en terraform init -backend-config="bucket=..."
  # (ver scripts/tf.sh)
  backend "gcs" {
    prefix = "fuentes/fuente-api"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
