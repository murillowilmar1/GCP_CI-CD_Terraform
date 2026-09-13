variable "project_id" {
  description = "Proyecto GCP donde se crea el job."
  type        = string
}

variable "region" {
  description = "Región del job."
  type        = string
}

variable "name" {
  description = "Nombre del Cloud Run Job (ej. \"fuente-postgres-raw\")."
  type        = string
}

variable "image" {
  description = "Imagen de contenedor (Artifact Registry) que corre el job.py de esta etapa."
  type        = string
}

variable "service_account" {
  description = "Email de la service account con la que corre el job."
  type        = string
}

variable "env_vars" {
  description = "Variables de entorno inyectadas al contenedor (buckets, dataset, etc.)."
  type        = map(string)
  default     = {}
}

variable "args" {
  description = "Argumentos pasados al entrypoint del contenedor."
  type        = list(string)
  default     = []
}

variable "command" {
  description = "Override del entrypoint del contenedor. Vacío = usa el ENTRYPOINT de la imagen."
  type        = list(string)
  default     = []
}

variable "cpu" {
  description = "CPU asignada al contenedor (ej. \"1\", \"2\")."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memoria asignada al contenedor (ej. \"512Mi\", \"2Gi\")."
  type        = string
  default     = "512Mi"
}

variable "timeout_seconds" {
  description = "Tiempo máximo de ejecución del job, en segundos."
  type        = number
  default     = 3600
}

variable "max_retries" {
  description = "Reintentos ante fallo de la ejecución."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Si true, Terraform no puede destruir el job (protección nativa de Cloud Run Jobs). false en dev, true en prod."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels del job."
  type        = map(string)
  default     = {}
}
