# Equivalente al módulo "codepipeline" de la versión AWS: define UN trigger
# de Cloud Build (2da generación, sobre un repo conectado vía Developer
# Connect) con su path filter y sus substitutions.
#
# Ambos modos usan developer_connect_event_config + push, porque
# source_to_build (el mecanismo "clásico" para triggers manuales) no soporta
# repos conectados vía Developer Connect — solo GitHub app clásica,
# Bitbucket Server o Cloud Source Repositories. La diferencia entre "push"
# y "manual" es el included_files:
#   - "push":   el real, filtra por la carpeta de la fuente -> dispara solo
#               cuando el push toca esa carpeta.
#   - "manual": un path que nunca existe en un commit real, así el webhook
#               de GitHub jamás hace match y el trigger nunca se autodispara.
#               El path filter NO aplica a una invocación manual
#               (gcloud builds triggers run / consola), así que sigue
#               pudiendo correrse a mano con --substitutions=_FUENTE=x.

locals {
  # Ruta que nunca va a existir en el repo real: garantiza que el webhook
  # de push jamás haga match y el trigger quede "manual only" en la práctica.
  manual_only_included_files = ["__manual-trigger-only__/**"]

  included_files = var.trigger_mode == "push" ? var.included_files : local.manual_only_included_files
}

resource "google_cloudbuild_trigger" "this" {
  project     = var.project_id
  location    = var.location
  name        = var.name
  description = var.description
  tags        = var.tags

  service_account = var.service_account
  substitutions   = var.substitutions
  filename        = var.filename
  included_files  = local.included_files

  developer_connect_event_config {
    git_repository_link = var.git_repository_link

    push {
      branch = var.branch
    }
  }

  dynamic "approval_config" {
    for_each = var.approval_required ? [1] : []
    content {
      approval_required = true
    }
  }
}
