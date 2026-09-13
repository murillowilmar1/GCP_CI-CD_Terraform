output "developer_connect_installation_state" {
  description = "Estado de la conexión a GitHub. Si stage = PENDING_USER_OAUTH, abrir action_uri y autorizar antes de re-aplicar."
  value       = google_developer_connect_connection.github.installation_state
}

output "terraform_cicd_service_account_email" {
  description = "Service account que ejecuta los builds de prod."
  value       = google_service_account.terraform_cicd.email
}

output "promote_plan_trigger_name" {
  value = module.promote_plan.trigger_name
}

output "promote_apply_trigger_name" {
  value = module.promote_apply.trigger_name
}
