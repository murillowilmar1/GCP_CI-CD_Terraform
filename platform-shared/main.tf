terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }

  # bucket real se pasa en terraform init -backend-config="bucket=..."
  # (uno distinto por proyecto/entorno, ver scripts/tf.sh)
  backend "gcs" {
    prefix = "platform-shared"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  common_labels = merge(var.labels, {
    environment = var.environment
    managed_by  = "terraform"
    layer       = "platform-shared"
  })

  # APIs usadas por esta capa y por el resto de las capas (cicd, cicd-prod,
  # fuentes/*) que dependen de que el proyecto ya las tenga habilitadas.
  required_apis = [
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "dataproc.googleapis.com",
    "run.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "developerconnect.googleapis.com",
    "artifactregistry.googleapis.com",
    "eventarc.googleapis.com",
    "secretmanager.googleapis.com",
    "composer.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Buckets de datos (equivalente a los buckets S3 raw/stage/analytics)
# ---------------------------------------------------------------------------

resource "google_storage_bucket" "raw" {
  name                        = "${var.name_prefix}-raw"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = var.environment == "dev"
  labels                      = local.common_labels

  versioning {
    enabled = var.environment == "prod"
  }

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket" "stage" {
  name                        = "${var.name_prefix}-stage"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = var.environment == "dev"
  labels                      = local.common_labels

  versioning {
    enabled = var.environment == "prod"
  }

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket" "analytics" {
  name                        = "${var.name_prefix}-analytics"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = var.environment == "dev"
  labels                      = local.common_labels

  versioning {
    enabled = var.environment == "prod"
  }

  depends_on = [google_project_service.required]
}

# Bucket de resultados de queries (equivalente al bucket de resultados de Athena).
# BigQuery no lo necesita para correr queries, pero sirve como destino de
# exports/extracts (EXPORT DATA, bq extract) que las fuentes puedan generar.
resource "google_storage_bucket" "query_results" {
  name                        = "${var.name_prefix}-query-results"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true
  labels                      = local.common_labels

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Catálogo de datos (equivalente a Glue Catalog): un dataset de BigQuery
# compartido; cada fuente crea sus propias tablas dentro (o datasets propios
# si se prefiere aislar por fuente, a decidir cuando escribamos las fuentes).
# ---------------------------------------------------------------------------

resource "google_bigquery_dataset" "catalog" {
  dataset_id  = var.bq_dataset_id
  project     = var.project_id
  location    = var.region
  description = "Catálogo de datos compartido (equivalente a Glue Catalog)"
  labels      = local.common_labels

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Artifact Registry: repo Docker compartido donde los pipelines de cada
# fuente suben las imágenes de sus jobs (raw/stage/analytics) antes del
# `terraform apply` de su capa fuentes/<fuente>/infra.
# ---------------------------------------------------------------------------

resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "multifuente"
  format        = "DOCKER"
  description   = "Imágenes de los jobs (Cloud Run Jobs) de todas las fuentes"
  labels        = local.common_labels

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Service account compartida, usada por los jobs de Dataproc/Cloud Run y
# Cloud Functions de todas las fuentes para leer/escribir en los buckets y
# el dataset compartido.
# ---------------------------------------------------------------------------

resource "google_service_account" "pipeline_sa" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-pipeline-sa"
  display_name = "Service account compartida de pipelines (${var.environment})"

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket_iam_member" "pipeline_sa_raw" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline_sa.email}"
}

resource "google_storage_bucket_iam_member" "pipeline_sa_stage" {
  bucket = google_storage_bucket.stage.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline_sa.email}"
}

resource "google_storage_bucket_iam_member" "pipeline_sa_analytics" {
  bucket = google_storage_bucket.analytics.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline_sa.email}"
}

resource "google_storage_bucket_iam_member" "pipeline_sa_query_results" {
  bucket = google_storage_bucket.query_results.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline_sa.email}"
}

resource "google_bigquery_dataset_iam_member" "pipeline_sa_catalog" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.catalog.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pipeline_sa.email}"
}

resource "google_project_iam_member" "pipeline_sa_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.pipeline_sa.email}"
}

resource "google_project_iam_member" "pipeline_sa_dataproc_worker" {
  project = var.project_id
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${google_service_account.pipeline_sa.email}"
}

# ---------------------------------------------------------------------------
# Cloud Functions 2nd gen usa, por defecto, la service account de Compute
# por defecto del proyecto para su build interno (empaquetar el código en
# una imagen). Esta organización tiene deshabilitado el otorgamiento
# automático de roles a las service accounts por defecto, así que sin esto
# el build de cualquier Cloud Function falla con "missing permission on the
# build service account".
# ---------------------------------------------------------------------------

locals {
  default_compute_sa = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "compute_sa_cloudbuild_builder" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${local.default_compute_sa}"

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "compute_sa_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${local.default_compute_sa}"

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "compute_sa_logwriter" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.default_compute_sa}"

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "compute_sa_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${local.default_compute_sa}"

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Cloud Composer 2 necesita que su propio service agent tenga este rol para
# poder administrar IAM sobre otras service accounts (workloads de GKE por
# detrás). Sin esto, crear un entorno falla con "missing required
# permissions: iam.serviceAccounts.getIamPolicy, setIamPolicy".
# ---------------------------------------------------------------------------

resource "google_project_iam_member" "composer_service_agent_ext" {
  project = var.project_id
  role    = "roles/composer.ServiceAgentV2Ext"
  member  = "serviceAccount:service-${data.google_project.current.number}@cloudcomposer-accounts.iam.gserviceaccount.com"

  depends_on = [google_project_service.required]
}
