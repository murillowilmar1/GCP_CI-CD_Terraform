variable "project_id" {
  description = "Proyecto GCP donde se crea la función."
  type        = string
}

variable "region" {
  description = "Región de la función."
  type        = string
}

variable "name" {
  description = "Nombre de la función (ej. \"fuente-sqlserver-audit\")."
  type        = string
}

variable "description" {
  description = "Descripción de la función."
  type        = string
  default     = ""
}

variable "source_dir" {
  description = "Path local al directorio con el código fuente (ej. \"../src/audit\"). Se empaqueta en un zip y se sube a GCS."
  type        = string
}

variable "runtime" {
  description = "Runtime de Cloud Functions (2nd gen)."
  type        = string
  default     = "python312"
}

variable "entry_point" {
  description = "Nombre de la función (Python) que Cloud Functions invoca."
  type        = string
  default     = "main"
}

variable "service_account" {
  description = "Email de la service account con la que corre la función."
  type        = string
}

variable "env_vars" {
  description = "Variables de entorno inyectadas a la función."
  type        = map(string)
  default     = {}
}

variable "available_memory" {
  description = "Memoria disponible (ej. \"256M\", \"512M\")."
  type        = string
  default     = "256M"
}

variable "timeout_seconds" {
  description = "Timeout de cada invocación, en segundos."
  type        = number
  default     = 60
}

variable "min_instance_count" {
  description = "Instancias mínimas siempre activas (0 = scale to zero)."
  type        = number
  default     = 0
}

variable "max_instance_count" {
  description = "Instancias máximas concurrentes."
  type        = number
  default     = 1
}

variable "allow_unauthenticated" {
  description = "Si true, la función queda invocable sin autenticación (solo para demos; en un caso real preferir invocaciones autenticadas)."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels de la función."
  type        = map(string)
  default     = {}
}
