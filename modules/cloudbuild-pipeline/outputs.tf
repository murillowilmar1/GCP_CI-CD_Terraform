output "trigger_id" {
  description = "ID del trigger creado."
  value       = google_cloudbuild_trigger.this.trigger_id
}

output "trigger_name" {
  description = "Nombre del trigger creado."
  value       = google_cloudbuild_trigger.this.name
}
