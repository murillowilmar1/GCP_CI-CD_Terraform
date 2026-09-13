variable "dag_gcs_prefix" {
  description = "Output dag_gcs_prefix del módulo composer-environment (formato gs://bucket/dags)."
  type        = string
}

variable "dag_file_path" {
  description = "Path local al archivo .py del DAG."
  type        = string
}

variable "dag_file_name" {
  description = "Nombre del archivo dentro de la carpeta dags/ del bucket."
  type        = string
}
