output "raw_bucket" {
  description = "Nombre del bucket raw."
  value       = google_storage_bucket.raw.name
}

output "stage_bucket" {
  description = "Nombre del bucket stage."
  value       = google_storage_bucket.stage.name
}

output "analytics_bucket" {
  description = "Nombre del bucket analytics."
  value       = google_storage_bucket.analytics.name
}

output "query_results_bucket" {
  description = "Nombre del bucket de resultados de queries."
  value       = google_storage_bucket.query_results.name
}

output "bq_dataset_id" {
  description = "ID del dataset de BigQuery compartido (catálogo)."
  value       = google_bigquery_dataset.catalog.dataset_id
}

output "pipeline_service_account_email" {
  description = "Email de la service account compartida usada por los jobs de las fuentes."
  value       = google_service_account.pipeline_sa.email
}

output "artifact_registry_repository" {
  description = "ID del repo Docker (repository_id), para armar la URL de imagen: <region>-docker.pkg.dev/<project_id>/<este_valor>/<imagen>."
  value       = google_artifact_registry_repository.images.repository_id
}
