"""Cloud Function de auditoría de fuente-sqlserver (equivalente a una Lambda
de auditoría): recibe un evento HTTP y deja un registro en BigQuery
(tabla audit_log, creada por infra/main.tf).

Body esperado (JSON): {"fuente": "...", "etapa": "raw|stage|analytics",
"status": "ok|error", "mensaje": "..."}

Variables de entorno esperadas: PROJECT_ID, BQ_DATASET.
"""

import datetime
import os

import functions_framework
from google.cloud import bigquery

PROJECT_ID = os.environ["PROJECT_ID"]
BQ_DATASET = os.environ["BQ_DATASET"]

bq_client = bigquery.Client(project=PROJECT_ID)
TABLE_ID = f"{PROJECT_ID}.{BQ_DATASET}.audit_log"
print(TABLE_ID)


@functions_framework.http
def main(request):
    body = request.get_json(silent=True) or {}

    row = {
        "fuente": body.get("fuente", "fuente-sqlserver"),
        "etapa": body.get("etapa", "unknown"),
        "status": body.get("status", "unknown"),
        "mensaje": body.get("mensaje", ""),
        "timestamp": datetime.datetime.utcnow().isoformat(),
    }

    errors = bq_client.insert_rows_json(TABLE_ID, [row])
    if errors:
        return ({"ok": False, "errors": errors}, 500)

    return ({"ok": True, "row": row}, 200)
