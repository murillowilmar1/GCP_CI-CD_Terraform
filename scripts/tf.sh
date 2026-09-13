#!/usr/bin/env bash
# Helper para correr Terraform contra el módulo/entorno correctos.
#
# Uso:
#   scripts/tf.sh <directorio-del-modulo> <dev|prod> <init|plan|apply|destroy|fmt|validate|output> [args extra de terraform...]
#
# Ejemplos:
#   scripts/tf.sh platform-shared dev init
#   scripts/tf.sh platform-shared dev apply
#   scripts/tf.sh fuentes/fuente-postgres/infra dev plan
#   scripts/tf.sh cicd-prod prod apply -var="fuente=fuente-postgres"
#
# Convención de nombres de bucket de tfstate (uno por proyecto/entorno,
# bootstrapeado a mano una sola vez, ver README): "<name_prefix>-tfstate"
#   dev  -> lakehouse-aw-dev-tfstate
#   prod -> lakehouse-aw-prod-tfstate

set -euo pipefail

MODULE_DIR="${1:-}"
ENV="${2:-}"
ACTION="${3:-}"
shift 3 || true

if [[ -z "$MODULE_DIR" || -z "$ENV" || -z "$ACTION" ]]; then
  echo "Uso: $0 <directorio-del-modulo> <dev|prod> <init|plan|apply|destroy|fmt|validate|output> [args extra...]" >&2
  exit 1
fi

if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
  echo "Error: <env> debe ser 'dev' o 'prod', recibido: $ENV" >&2
  exit 1
fi

case "$ENV" in
  dev)  TFSTATE_BUCKET="lakehouse-aw-dev-tfstate" ;;
  prod) TFSTATE_BUCKET="lakehouse-aw-prod-tfstate" ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/$MODULE_DIR"
TFVARS_FILE="$REPO_ROOT/env/$ENV.tfvars"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: no existe el directorio $TARGET_DIR" >&2
  exit 1
fi

if [[ ! -f "$TARGET_DIR/backend.tf" && ! -f "$TARGET_DIR/main.tf" ]]; then
  echo "Error: $TARGET_DIR no parece un módulo raíz de Terraform (sin backend.tf/main.tf)" >&2
  exit 1
fi

echo "== módulo:   $MODULE_DIR"
echo "== entorno:  $ENV"
echo "== bucket:   $TFSTATE_BUCKET"
echo "== acción:   $ACTION"
echo

cd "$TARGET_DIR"

case "$ACTION" in
  init)
    terraform init -reconfigure -backend-config="bucket=${TFSTATE_BUCKET}" "$@"
    ;;
  fmt|validate)
    terraform "$ACTION" "$@"
    ;;
  plan|apply|destroy)
    if [[ -f "$TFVARS_FILE" ]]; then
      terraform "$ACTION" -var-file="$TFVARS_FILE" "$@"
    else
      terraform "$ACTION" "$@"
    fi
    ;;
  output)
    terraform output "$@"
    ;;
  *)
    echo "Error: acción desconocida '$ACTION'" >&2
    exit 1
    ;;
esac
