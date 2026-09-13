variable "project_id" {
  description = "Proyecto GCP del entorno (dev o prod)."
  type        = string
}

variable "region" {
  description = "Región de GCP."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "dev o prod."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment debe ser \"dev\" o \"prod\"."
  }
}

variable "name_prefix" {
  description = "Debe coincidir con el name_prefix de platform-shared para este entorno (para ubicar su bucket de tfstate)."
  type        = string
}

variable "composer_environment_size" {
  description = "Tamaño del entorno de Composer. SMALL para dev/demo."
  type        = string
  default     = "ENVIRONMENT_SIZE_SMALL"
}
