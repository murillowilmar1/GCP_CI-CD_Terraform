locals {
  source_name = "fuente-postgres"

  raw_bucket       = data.terraform_remote_state.platform.outputs.raw_bucket
  stage_bucket     = data.terraform_remote_state.platform.outputs.stage_bucket
  analytics_bucket = data.terraform_remote_state.platform.outputs.analytics_bucket
  bq_dataset_id    = data.terraform_remote_state.platform.outputs.bq_dataset_id
  service_account  = data.terraform_remote_state.platform.outputs.pipeline_service_account_email

  common_env = {
    SOURCE_NAME = local.source_name
    PROJECT_ID  = var.project_id
    BQ_DATASET  = local.bq_dataset_id
  }

  deletion_protection = var.environment == "prod"
}

module "raw" {
  source = "../../../modules/cloud-run-job"

  project_id      = var.project_id
  region          = var.region
  name            = "${local.source_name}-raw"
  image           = var.raw_image
  service_account = local.service_account

  env_vars = merge(local.common_env, {
    RAW_BUCKET = local.raw_bucket
  })

  deletion_protection = local.deletion_protection
  labels              = { fuente = local.source_name, etapa = "raw" }
}

module "stage" {
  source = "../../../modules/cloud-run-job"

  project_id      = var.project_id
  region          = var.region
  name            = "${local.source_name}-stage"
  image           = var.stage_image
  service_account = local.service_account

  env_vars = merge(local.common_env, {
    RAW_BUCKET   = local.raw_bucket
    STAGE_BUCKET = local.stage_bucket
  })

  deletion_protection = local.deletion_protection
  labels              = { fuente = local.source_name, etapa = "stage" }
}

module "analytics" {
  source = "../../../modules/cloud-run-job"

  project_id      = var.project_id
  region          = var.region
  name            = "${local.source_name}-analytics"
  image           = var.analytics_image
  service_account = local.service_account

  env_vars = merge(local.common_env, {
    STAGE_BUCKET     = local.stage_bucket
    ANALYTICS_BUCKET = local.analytics_bucket
  })

  deletion_protection = local.deletion_protection
  labels              = { fuente = local.source_name, etapa = "analytics" }
}
