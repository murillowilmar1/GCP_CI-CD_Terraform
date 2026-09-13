"""Etapa RAW de fuente-sqlserver: extrae de la fuente y aterriza en el bucket raw.

Corre como Cloud Run Job. Variables de entorno esperadas: RAW_BUCKET,
SOURCE_NAME (inyectadas por fuentes/fuente-sqlserver/infra/main.tf).
"""

import datetime
import json
import os

from google.cloud import storage

RAW_BUCKET = os.environ["RAW_BUCKET"]
SOURCE_NAME = os.environ.get("SOURCE_NAME", "fuente-sqlserver")


def extract() -> list[dict]:
    """Extrae de la base SQL Server origen.

    TODO: reemplazar por la extracción real, ej:
        import pyodbc
        conn = pyodbc.connect(
            f"DRIVER={{ODBC Driver 18 for SQL Server}};"
            f"SERVER={os.environ['SOURCE_DB_HOST']};"
            f"DATABASE={os.environ['SOURCE_DB_NAME']};"
            f"UID={os.environ['SOURCE_DB_USER']};"
            f"PWD={os.environ['SOURCE_DB_PASSWORD']}"
        )
        # ... query y fetch ...

    Genera datos sintéticos mientras tanto, para poder desplegar y correr
    el ejercicio de punta a punta sin una base real conectada.
    """
    now = datetime.datetime.utcnow().isoformat()
    return [
        {"id": i, "source": SOURCE_NAME, "extracted_at": now, "value": i * 20}
        for i in range(1, 11)
    ]


def main() -> None:
    rows = extract()
    ts = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
    blob_path = f"{SOURCE_NAME}/raw_{ts}.json"

    client = storage.Client()
    bucket = client.bucket(RAW_BUCKET)
    bucket.blob(blob_path).upload_from_string(
        "\n".join(json.dumps(r) for r in rows),
        content_type="application/json",
    )
    print(f"OK: {len(rows)} filas escritas en gs://{RAW_BUCKET}/{blob_path}")


if __name__ == "__main__":
    main()
