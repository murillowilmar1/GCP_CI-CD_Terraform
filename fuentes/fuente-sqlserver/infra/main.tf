locals {
  source_name = "fuente-sqlserver"

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

# ---------------------------------------------------------------------------
# Tabla de auditoría (destino de la Cloud Function de abajo).
# ---------------------------------------------------------------------------

resource "google_bigquery_table" "audit_log" {
  project    = var.project_id
  dataset_id = local.bq_dataset_id
  table_id   = "audit_log"
  labels     = { fuente = local.source_name }

  deletion_protection = local.deletion_protection

  schema = jsonencode([
    { name = "fuente", type = "STRING", mode = "REQUIRED" },
    { name = "etapa", type = "STRING", mode = "REQUIRED" },
    { name = "status", type = "STRING", mode = "REQUIRED" },
    { name = "mensaje", type = "STRING", mode = "NULLABLE" },
    { name = "timestamp", type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}

# ---------------------------------------------------------------------------
# Cloud Function de auditoría (equivalente a lambda-function), específica
# de esta fuente.
# ---------------------------------------------------------------------------

module "audit" {
  source = "../../../modules/cloud-function"

  project_id  = var.project_id
  region      = var.region
  name        = "${local.source_name}-audit"
  description = "Auditoría de corridas de ${local.source_name}"
  source_dir  = "${path.module}/../src/audit"
  entry_point = "main"
  runtime     = "python312"

  service_account = local.service_account

  env_vars = {
    PROJECT_ID = var.project_id
    BQ_DATASET = local.bq_dataset_id
  }

  labels = { fuente = local.source_name, etapa = "audit" }

  depends_on = [google_bigquery_table.audit_log]
}
