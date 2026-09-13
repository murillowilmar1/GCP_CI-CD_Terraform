variable "project_id" {
  description = "ID del proyecto GCP (dev o prod, según el env)."
  type        = string
}

variable "region" {
  description = "Región de GCP para buckets, dataset y recursos regionales."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Nombre del entorno (dev|prod). Se usa como prefijo/label en los recursos."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment debe ser \"dev\" o \"prod\"."
  }
}

variable "name_prefix" {
  description = "Prefijo corto para nombrar recursos globalmente únicos (buckets). Ej: \"multifuente-dev\"."
  type        = string
}

variable "bq_dataset_id" {
  description = "ID del dataset de BigQuery compartido (catálogo)."
  type        = string
  default     = "multifuente_catalog"
}

variable "labels" {
  description = "Labels comunes aplicadas a los recursos de la plataforma."
  type        = map(string)
  default     = {}
}
