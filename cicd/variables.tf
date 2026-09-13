variable "project_id" {
  description = "Proyecto GCP de dev."
  type        = string
}

variable "region" {
  description = "Región de GCP (Developer Connect + Cloud Build son regionales)."
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Debe coincidir con el name_prefix usado en platform-shared para dev (usado para derivar el nombre del bucket de tfstate)."
  type        = string
}

variable "github_clone_uri" {
  description = "URL de clone del repo de GitHub."
  type        = string
  default     = "https://github.com/murillowilmar1/GCP_CI-CD_Terraform.git"
}

variable "dev_branch" {
  description = "Rama que dispara el auto-apply de dev."
  type        = string
  default     = "dev"
}

variable "fuentes" {
  description = "Nombres de las carpetas bajo fuentes/ para las que crear un trigger de dev."
  type        = list(string)
  default     = ["fuente-postgres", "fuente-sqlserver"]
}
