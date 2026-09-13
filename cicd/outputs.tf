output "developer_connect_installation_state" {
  description = "Estado de la conexión a GitHub. Si stage = PENDING_USER_OAUTH, abrir action_uri y autorizar antes de re-aplicar."
  value       = google_developer_connect_connection.github.installation_state
}

output "terraform_cicd_service_account_email" {
  description = "Service account que ejecuta los builds de dev."
  value       = google_service_account.terraform_cicd.email
}

output "dev_trigger_names" {
  description = "Nombres de los triggers de dev creados, uno por fuente."
  value       = { for k, m in module.dev_trigger : k => m.trigger_name }
}
