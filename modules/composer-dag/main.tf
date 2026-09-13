# Sube un DAG al bucket de Composer. dag_gcs_prefix viene con forma
# "gs://<bucket>/dags" — extraemos el nombre del bucket para poder usar
# google_storage_bucket_object (que necesita el bucket "pelado", sin gs://
# ni el resto del path).

locals {
  bucket_name = regex("^gs://([^/]+)/", "${var.dag_gcs_prefix}/")[0]
}

resource "google_storage_bucket_object" "dag" {
  name   = "dags/${var.dag_file_name}"
  bucket = local.bucket_name
  source = var.dag_file_path
}
