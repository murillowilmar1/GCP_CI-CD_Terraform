output "composer_environment_name" {
  value = module.composer.environment_name
}

output "airflow_uri" {
  description = "URL de la UI de Airflow para ver/correr el DAG manualmente."
  value       = module.composer.airflow_uri
}
