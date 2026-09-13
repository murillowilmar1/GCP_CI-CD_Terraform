# Entorno de Cloud Composer (Airflow administrado). A diferencia de
# cloud-run-job/cloud-function, esto NO es serverless: corre 24/7 y genera
# costo continuo (del orden de varios cientos de USD/mes incluso sin correr
# DAGs) y tarda 20-40 minutos en crearse/destruirse. Pensarlo dos veces
# antes de aplicar esto en más de un lugar — normalmente se comparte UN
# entorno entre muchas fuentes, no uno por fuente.

resource "google_composer_environment" "this" {
  name    = var.name
  project = var.project_id
  region  = var.region

  config {
    environment_size = var.environment_size

    software_config {
      image_version = var.image_version
      env_variables = var.env_variables
      pypi_packages = var.pypi_packages
    }

    node_config {
      service_account = var.service_account
    }
  }

  labels = var.labels
}
