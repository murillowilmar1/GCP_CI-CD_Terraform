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
  description = "dev o prod. Controla deletion_protection de los jobs."
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

# --- Imágenes de los jobs -----------------------------------------------
# Generadas automáticamente por el pipeline (cloudbuild.yaml) en
# infra/images.auto.tfvars antes de correr terraform — no tienen default a
# propósito, para que falle claro si el paso de build+push no corrió.

variable "raw_image" {
  description = "Imagen (con digest) del job de la etapa raw."
  type        = string
}

variable "stage_image" {
  description = "Imagen (con digest) del job de la etapa stage."
  type        = string
}

variable "analytics_image" {
  description = "Imagen (con digest) del job de la etapa analytics."
  type        = string
}
