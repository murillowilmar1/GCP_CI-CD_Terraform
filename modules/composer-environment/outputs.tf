output "dag_gcs_prefix" {
  description = "Prefijo GCS (gs://bucket/dags) donde Airflow busca los DAGs de este entorno."
  value       = google_composer_environment.this.config[0].dag_gcs_prefix
}

output "environment_name" {
  value = google_composer_environment.this.name
}

output "airflow_uri" {
  description = "URL de la UI de Airflow."
  value       = google_composer_environment.this.config[0].airflow_uri
}
