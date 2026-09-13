# Lee los outputs de platform-shared (mismo proyecto/entorno) para no
# tener que repetir nombres de buckets/dataset/service account a mano.
data "terraform_remote_state" "platform" {
  backend = "gcs"

  config = {
    bucket = "${var.name_prefix}-tfstate"
    prefix = "platform-shared"
  }
}
