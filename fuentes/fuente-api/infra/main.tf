# ADVERTENCIA: esto crea un entorno de Cloud Composer real. A diferencia
# del resto del laboratorio (Cloud Run Jobs, Cloud Functions — serverless,
# pago por uso), Composer corre 24/7 y genera costo continuo (del orden de
# varios cientos de USD/mes) además de tardar 20-40 minutos en crear o
# destruir. No aplicar esta capa sin confirmar que realmente se quiere ese
# gasto.

locals {
  source_name = "fuente-api"

  raw_bucket      = data.terraform_remote_state.platform.outputs.raw_bucket
  stage_bucket    = data.terraform_remote_state.platform.outputs.stage_bucket
  bq_dataset_id   = data.terraform_remote_state.platform.outputs.bq_dataset_id
  service_account = data.terraform_remote_state.platform.outputs.pipeline_service_account_email
}

module "composer" {
  source = "../../../modules/composer-environment"

  project_id       = var.project_id
  region           = var.region
  name             = "${local.source_name}-${var.environment}"
  environment_size = var.composer_environment_size
  service_account  = local.service_account

  env_variables = {
    RAW_BUCKET   = local.raw_bucket
    STAGE_BUCKET = local.stage_bucket
    PROJECT_ID   = var.project_id
    BQ_DATASET   = local.bq_dataset_id
  }

  pypi_packages = {
    pandas                = ""
    pyarrow               = ""
    google-cloud-bigquery = ""
    requests              = ""
  }

  labels = { fuente = local.source_name }
}

module "dag" {
  source = "../../../modules/composer-dag"

  dag_gcs_prefix = module.composer.dag_gcs_prefix
  dag_file_path  = "${path.module}/../src/dag.py"
  dag_file_name  = "fuente_api_pipeline.py"
}
