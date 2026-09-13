terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }

  # bucket real se pasa en terraform init -backend-config="bucket=..."
  # (ver scripts/tf.sh)
  backend "gcs" {
    prefix = "cicd"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
}

# ---------------------------------------------------------------------------
# Conexión a GitHub vía Developer Connect (una por proyecto).
#
# IMPORTANTE - flujo en dos pasos, inherente al producto:
#   1. `terraform apply` crea la conexión en estado PENDING_USER_OAUTH.
#      Correr `terraform output developer_connect_installation_state` y
#      abrir el `action_uri` que ahí aparece: autoriza la GitHub App e
#      instálala sobre el repo murillowilmar1/GCP_CI-CD_Terraform.
#   2. Volver a correr `terraform apply`: ahora sí crea el
#      git_repository_link y los triggers (que dependen de la conexión ya
#      autorizada).
# ---------------------------------------------------------------------------

# El service agent de Developer Connect necesita crear/administrar un
# secreto en Secret Manager para guardar el token de OAuth de GitHub tras
# la autorización interactiva. Sin esto, el paso de autorización falla con
# "could not create a secret: permission_denied".
resource "google_project_iam_member" "devconnect_secret_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-devconnect.iam.gserviceaccount.com"
}

resource "google_developer_connect_connection" "github" {
  project       = var.project_id
  location      = var.region
  connection_id = "github-multifuente"

  github_config {
    github_app = "DEVELOPER_CONNECT"
  }

  depends_on = [google_project_iam_member.devconnect_secret_admin]
}

resource "google_developer_connect_git_repository_link" "repo" {
  project                = var.project_id
  location               = var.region
  parent_connection      = google_developer_connect_connection.github.connection_id
  git_repository_link_id = "multi-fuente-demo-gcp"
  clone_uri              = var.github_clone_uri

  depends_on = [google_developer_connect_connection.github]
}

# ---------------------------------------------------------------------------
# Service account que ejecuta los builds de Terraform (plan+apply) en dev.
# roles/editor es deliberadamente amplio para no tener que ir agregando
# permisos puntuales por cada tipo de recurso que las fuentes vayan
# necesitando (Dataproc, Cloud Run, Cloud Functions, BigQuery, etc.) — es
# un laboratorio, no un entorno con compliance estricto. Endurecer luego
# con un rol custom si hace falta.
# ---------------------------------------------------------------------------

resource "google_service_account" "terraform_cicd" {
  project      = var.project_id
  account_id   = "cicd-terraform-dev"
  display_name = "Cloud Build - terraform plan/apply (dev)"
}

resource "google_project_iam_member" "terraform_cicd_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.terraform_cicd.email}"
}

# Requerido para que la SA del trigger pueda leer el token de OAuth de
# GitHub que administra Developer Connect (si no, la creación del trigger
# falla con "insufficient permissions... to project").
resource "google_project_iam_member" "terraform_cicd_devconnect_token" {
  project = var.project_id
  role    = "roles/developerconnect.readTokenAccessor"
  member  = "serviceAccount:${google_service_account.terraform_cicd.email}"
}

# Requerido para que esta SA (no la de Cloud Build por defecto) pueda ser
# usada como identidad de ejecución de un trigger/build.
resource "google_project_iam_member" "terraform_cicd_builder" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.terraform_cicd.email}"
}

resource "google_project_iam_member" "terraform_cicd_logwriter" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.terraform_cicd.email}"
}

# Explícito además de roles/editor: el build necesita subir las imágenes de
# los jobs (docker push) al repo de Artifact Registry de platform-shared.
resource "google_project_iam_member" "terraform_cicd_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.terraform_cicd.email}"
}

# Cloud Build necesita poder "actuar como" la SA custom del trigger para
# poder correr builds usándola como identidad.
resource "google_service_account_iam_member" "cloudbuild_can_act_as_terraform_sa" {
  service_account_id = google_service_account.terraform_cicd.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# ---------------------------------------------------------------------------
# Un trigger de dev por fuente: push a la rama `dev` + path filter sobre la
# carpeta de esa fuente -> nunca se pisan entre sí. plan+apply corren como
# 2 steps del mismo build (ver fuentes/<fuente>/cloudbuild.yaml).
# ---------------------------------------------------------------------------

module "dev_trigger" {
  source   = "../modules/cloudbuild-pipeline"
  for_each = toset(var.fuentes)

  project_id  = var.project_id
  location    = var.region
  name        = "dev-${each.value}"
  description = "Dev auto-apply para ${each.value} (push a ${var.dev_branch})"

  git_repository_link = google_developer_connect_git_repository_link.repo.name
  filename            = "fuentes/${each.value}/cloudbuild.yaml"
  service_account     = google_service_account.terraform_cicd.name

  trigger_mode   = "push"
  branch         = "^${var.dev_branch}$"
  included_files = ["fuentes/${each.value}/**"]

  substitutions = {
    _TFSTATE_BUCKET = "${var.name_prefix}-tfstate"
    _ENV            = "dev"
  }

  approval_required = false
}
