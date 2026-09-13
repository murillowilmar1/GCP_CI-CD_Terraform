variable "project_id" {
  description = "Proyecto GCP donde se crea el trigger."
  type        = string
}

variable "location" {
  description = "Región del trigger de Cloud Build. Debe coincidir con la región de la conexión de Developer Connect (los triggers de 2da generación son regionales)."
  type        = string
}

variable "name" {
  description = "Nombre del trigger."
  type        = string
}

variable "description" {
  description = "Descripción del trigger."
  type        = string
  default     = ""
}

variable "git_repository_link" {
  description = "Resource name completo del git_repository_link de Developer Connect (formato: projects/P/locations/L/connections/C/gitRepositoryLinks/R)."
  type        = string
}

variable "filename" {
  description = "Ruta (dentro del repo) del archivo cloudbuild.yaml que este trigger debe ejecutar."
  type        = string
}

variable "service_account" {
  description = "Resource name completo de la service account que ejecuta el build (formato: projects/P/serviceAccounts/EMAIL)."
  type        = string
}

variable "substitutions" {
  description = "Substitutions inyectadas en el build (deben empezar con _)."
  type        = map(string)
  default     = {}
}

variable "trigger_mode" {
  description = <<-EOT
    "push":   se dispara automáticamente con push a `branch` + `included_files` reales
              (uso: pipelines de dev, un trigger por fuente).
    "manual": usa el mismo mecanismo (developer_connect_event_config + push), pero con
              un `included_files` que apunta a una ruta que nunca existe en un commit
              real (ver locals en main.tf). El webhook de GitHub nunca hace match, así
              que en la práctica solo se dispara a mano
              (gcloud builds triggers run --branch=... --substitutions=...).
              Esto es necesario porque, a la fecha, source_to_build no soporta repos
              conectados vía Developer Connect (solo GitHub app clásica / Bitbucket
              Server / Cloud Source Repositories) — ver README para el detalle.
  EOT
  type        = string

  validation {
    condition     = contains(["push", "manual"], var.trigger_mode)
    error_message = "trigger_mode debe ser \"push\" o \"manual\"."
  }
}

variable "branch" {
  description = "Patrón de rama (regex) para el push event config. Ej: \"^dev$\" o \"^main$\"."
  type        = string
}

variable "included_files" {
  description = "Path filter (glob) real, solo aplica cuando trigger_mode = \"push\". Ej: [\"fuentes/fuente-postgres/**\"]. Ignorado (sobrescrito por el sentinel interno) cuando trigger_mode = \"manual\"."
  type        = list(string)
  default     = null
}

variable "approval_required" {
  description = "Si true, el build queda pausado esperando aprobación manual antes de ejecutar los steps."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags del trigger."
  type        = list(string)
  default     = []
}
