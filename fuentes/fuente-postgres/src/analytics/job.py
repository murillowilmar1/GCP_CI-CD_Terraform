"""Etapa ANALYTICS de fuente-postgres: toma el último stage y lo carga en
BigQuery (catálogo compartido de platform-shared).

Variables de entorno esperadas: STAGE_BUCKET, PROJECT_ID, BQ_DATASET,
SOURCE_NAME.
"""

import os

import pandas as pd
from google.cloud import bigquery, storage

STAGE_BUCKET = os.environ["STAGE_BUCKET"]
BQ_PROJECT = os.environ["PROJECT_ID"]
BQ_DATASET = os.environ["BQ_DATASET"]
SOURCE_NAME = os.environ.get("SOURCE_NAME", "fuente-postgres")


def latest_stage_blob(client: storage.Client) -> storage.Blob:
    blobs = list(client.list_blobs(STAGE_BUCKET, prefix=f"{SOURCE_NAME}/stage_"))
    if not blobs:
        raise RuntimeError(f"No hay archivos stage para {SOURCE_NAME} en gs://{STAGE_BUCKET}")
    return max(blobs, key=lambda b: b.name)


def main() -> None:
    storage_client = storage.Client()
    blob = latest_stage_blob(storage_client)

    local_path = "/tmp/stage.parquet"
    blob.download_to_filename(local_path)
    df = pd.read_parquet(local_path)

    bq_client = bigquery.Client(project=BQ_PROJECT)
    table_id = f"{BQ_PROJECT}.{BQ_DATASET}.{SOURCE_NAME.replace('-', '_')}"

    job = bq_client.load_table_from_dataframe(
        df,
        table_id,
        job_config=bigquery.LoadJobConfig(write_disposition="WRITE_APPEND"),
    )
    job.result()
    print(f"OK: {len(df)} filas cargadas en {table_id}")


if __name__ == "__main__":
    main()
