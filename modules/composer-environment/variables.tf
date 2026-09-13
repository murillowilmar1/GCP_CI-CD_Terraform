variable "project_id" {
  description = "Proyecto GCP donde se crea el entorno."
  type        = string
}

variable "region" {
  description = "Región del entorno."
  type        = string
}

variable "name" {
  description = "Nombre del entorno de Composer."
  type        = string
}

variable "image_version" {
  description = "Versión de imagen de Composer/Airflow. \"composer-2-airflow-2\" toma la última versión 2.x estable."
  type        = string
  default     = "composer-2-airflow-2"
}

variable "environment_size" {
  description = "Tamaño del entorno (ENVIRONMENT_SIZE_SMALL|MEDIUM|LARGE). SMALL es el más barato, pensado para dev/demo."
  type        = string
  default     = "ENVIRONMENT_SIZE_SMALL"
}

variable "service_account" {
  description = "Email de la service account con la que corren los workers de Airflow (tareas de los DAGs)."
  type        = string
}

variable "env_variables" {
  description = "Variables de entorno inyectadas a todos los workers de Airflow (accesibles vía os.environ en los DAGs)."
  type        = map(string)
  default     = {}
}

variable "pypi_packages" {
  description = "Paquetes Python adicionales a instalar en el entorno (map paquete -> constraint de versión, \"\" = cualquiera)."
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels del entorno."
  type        = map(string)
  default     = {}
}
