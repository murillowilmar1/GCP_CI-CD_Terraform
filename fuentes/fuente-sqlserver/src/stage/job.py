"""Etapa STAGE de fuente-sqlserver: toma el último raw y lo deja limpio/parquet
en el bucket stage.

Variables de entorno esperadas: RAW_BUCKET, STAGE_BUCKET, SOURCE_NAME.
"""

import datetime
import io
import json
import os

import pandas as pd
from google.cloud import storage

RAW_BUCKET = os.environ["RAW_BUCKET"]
STAGE_BUCKET = os.environ["STAGE_BUCKET"]
SOURCE_NAME = os.environ.get("SOURCE_NAME", "fuente-sqlserver")


def latest_raw_blob(client: storage.Client) -> storage.Blob:
    blobs = list(client.list_blobs(RAW_BUCKET, prefix=f"{SOURCE_NAME}/raw_"))
    if not blobs:
        raise RuntimeError(f"No hay archivos raw para {SOURCE_NAME} en gs://{RAW_BUCKET}")
    return max(blobs, key=lambda b: b.name)


def main() -> None:
    client = storage.Client()
    blob = latest_raw_blob(client)
    rows = [json.loads(line) for line in blob.download_as_text().splitlines() if line.strip()]

    df = pd.DataFrame(rows)
    df["processed_at"] = datetime.datetime.utcnow().isoformat()

    ts = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
    blob_path = f"{SOURCE_NAME}/stage_{ts}.parquet"

    buf = io.BytesIO()
    df.to_parquet(buf, index=False)
    client.bucket(STAGE_BUCKET).blob(blob_path).upload_from_string(
        buf.getvalue(), content_type="application/octet-stream"
    )
    print(f"OK: {len(df)} filas escritas en gs://{STAGE_BUCKET}/{blob_path}")


if __name__ == "__main__":
    main()
