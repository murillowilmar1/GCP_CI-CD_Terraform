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
    prefix = "cicd-prod"
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
# Conexión a GitHub vía Developer Connect (independiente de la de dev: cada
# proyecto tiene la suya). Mismo flujo en dos pasos que en cicd/, ver ese
# archivo para el detalle del action_uri / PENDING_USER_OAUTH.
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
# Service account que ejecuta los builds de Terraform (plan+apply) en prod.
# ---------------------------------------------------------------------------

resource "google_service_account" "terraform_cicd" {
  project      = var.project_id
  account_id   = "cicd-terraform-prod"
  display_name = "Cloud Build - terraform plan/apply (prod)"
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

resource "google_service_account_iam_member" "cloudbuild_can_act_as_terraform_sa" {
  service_account_id = google_service_account.terraform_cicd.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# ---------------------------------------------------------------------------
# Pipeline paramétrico de promoción a prod: UN par de triggers (plan/apply),
# no uno por fuente. Se corren a mano pasando --substitutions=_FUENTE=<fuente>.
#
# Flujo esperado (manual, antes de correr esto):
#   git checkout dev -- fuentes/<fuente>   # sync acotado de esa carpeta
#   git commit && git push origin main
#
# Luego:
#   1. gcloud builds triggers run promote-plan  --region=... --branch=main --substitutions=_FUENTE=fuente-postgres
#      -> revisar el diff en los logs del build.
#   2. gcloud builds triggers run promote-apply --region=... --branch=main --substitutions=_FUENTE=fuente-postgres
#      -> queda pausado esperando aprobación (Cloud Build approval nativo);
#         aprobar desde consola o `gcloud builds approve`.
# ---------------------------------------------------------------------------

module "promote_plan" {
  source = "../modules/cloudbuild-pipeline"

  project_id  = var.project_id
  location    = var.region
  name        = "promote-plan"
  description = "Promoción a prod - terraform plan paramétrico (_FUENTE). Solo manual."

  git_repository_link = google_developer_connect_git_repository_link.repo.name
  filename            = "cicd-prod/cloudbuild-plan.yaml"
  service_account     = google_service_account.terraform_cicd.name

  trigger_mode = "manual"
  branch       = "^${var.main_branch}$"

  substitutions = {
    _FUENTE         = "CHANGE_ME"
    _TFSTATE_BUCKET = "${var.name_prefix}-tfstate"
    _ENV            = "prod"
  }

  approval_required = false
}

module "promote_apply" {
  source = "../modules/cloudbuild-pipeline"

  project_id  = var.project_id
  location    = var.region
  name        = "promote-apply"
  description = "Promoción a prod - terraform apply paramétrico (_FUENTE). Solo manual, requiere aprobación."

  git_repository_link = google_developer_connect_git_repository_link.repo.name
  filename            = "cicd-prod/cloudbuild-apply.yaml"
  service_account     = google_service_account.terraform_cicd.name

  trigger_mode = "manual"
  branch       = "^${var.main_branch}$"

  substitutions = {
    _FUENTE         = "CHANGE_ME"
    _TFSTATE_BUCKET = "${var.name_prefix}-tfstate"
    _ENV            = "prod"
  }

  approval_required = true
}
