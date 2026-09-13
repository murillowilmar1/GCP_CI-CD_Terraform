variable "project_id" {
  description = "Proyecto GCP de prod."
  type        = string
}

variable "region" {
  description = "Región de GCP (Developer Connect + Cloud Build son regionales)."
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Debe coincidir con el name_prefix usado en platform-shared para prod (usado para derivar el nombre del bucket de tfstate, que también se reusa para guardar los tfplan de la promoción)."
  type        = string
}

variable "github_clone_uri" {
  description = "URL de clone del repo de GitHub."
  type        = string
  default     = "https://github.com/murillowilmar1/GCP_CI-CD_Terraform.git"
}

variable "main_branch" {
  description = "Rama desde la que se promueve a prod."
  type        = string
  default     = "main"
}
