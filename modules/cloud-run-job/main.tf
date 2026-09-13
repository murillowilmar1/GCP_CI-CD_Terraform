# Equivalente al módulo "glue-job" de la versión AWS: una definición
# reutilizable de procesamiento (Cloud Run Job) que se puede invocar muchas
# veces (gcloud run jobs execute) sin que Terraform tenga que recrear nada
# entre corridas — a diferencia de Dataproc Serverless (Batches), donde cada
# ejecución es un recurso nuevo. Cada etapa (raw/stage/analytics) de cada
# fuente es una instancia de este módulo, empaquetando su propio job.py en
# una imagen de contenedor.

resource "google_cloud_run_v2_job" "this" {
  name     = var.name
  project  = var.project_id
  location = var.region

  deletion_protection = var.deletion_protection
  labels              = var.labels

  template {
    template {
      service_account = var.service_account
      max_retries     = var.max_retries
      timeout         = "${var.timeout_seconds}s"

      containers {
        image   = var.image
        command = length(var.command) > 0 ? var.command : null
        args    = length(var.args) > 0 ? var.args : null

        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }

        dynamic "env" {
          for_each = var.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }
  }
}
