output "function_name" {
  description = "Nombre de la función."
  value       = google_cloudfunctions2_function.this.name
}

output "function_uri" {
  description = "URL HTTPS de invocación de la función."
  value       = google_cloudfunctions2_function.this.service_config[0].uri
}
