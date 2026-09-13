# Equivalente al módulo "lambda-function" de la versión AWS: empaqueta el
# código fuente (zip) y despliega una Cloud Function 2nd gen.

data "archive_file" "source" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.build/${var.name}.zip"
}

# Bucket propio por función (nombre único: project_id ya es único
# globalmente, "-fn-<name>" evita colisión entre funciones del mismo
# proyecto).
resource "google_storage_bucket" "source" {
  name                        = "${var.project_id}-fn-${var.name}"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket_object" "source" {
  name   = "source/${data.archive_file.source.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.source.output_path
}

resource "google_cloudfunctions2_function" "this" {
  name        = var.name
  project     = var.project_id
  location    = var.region
  description = var.description
  labels      = var.labels

  build_config {
    runtime     = var.runtime
    entry_point = var.entry_point

    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.source.name
      }
    }
  }

  service_config {
    available_memory      = var.available_memory
    timeout_seconds       = var.timeout_seconds
    min_instance_count    = var.min_instance_count
    max_instance_count    = var.max_instance_count
    service_account_email = var.service_account
    environment_variables = var.env_vars
  }
}

# Invocación sin autenticación, solo si se pide explícitamente (demo/lab).
resource "google_cloud_run_service_iam_member" "invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [google_cloudfunctions2_function.this]
}
