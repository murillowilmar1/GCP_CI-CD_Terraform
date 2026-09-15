"""DAG de ejemplo para fuente-api: extrae el pronóstico del clima de
Open-Meteo (api.open-meteo.com — API pública real, gratis, sin API key),
transforma y carga a BigQuery.

A diferencia de fuente-postgres/fuente-sqlserver (3 Cloud Run Jobs
independientes, sin orquestación automática entre ellos), acá Airflow SÍ
controla el orden y las dependencias explícitas entre etapas — el caso
típico donde Composer/Airflow tiene sentido frente a jobs sueltos.

Este archivo se sube solo al bucket de DAGs del entorno de Composer (ver
infra/main.tf, módulo composer-dag); Airflow lo recoge automáticamente,
sin necesidad de reiniciar nada.

Variables de entorno esperadas (inyectadas al entorno completo de Composer,
ver infra/main.tf): RAW_BUCKET, STAGE_BUCKET, PROJECT_ID, BQ_DATASET.
Opcionales: SOURCE_LAT, SOURCE_LON (default: Bogotá).
"""

from __future__ import annotations

import datetime
import io
import json
import os

from airflow.decorators import dag, task

SOURCE_NAME = "fuente-api"
RAW_BUCKET = os.environ["RAW_BUCKET"]
STAGE_BUCKET = os.environ["STAGE_BUCKET"]
PROJECT_ID = os.environ["PROJECT_ID"]
BQ_DATASET = os.environ["BQ_DATASET"]


@dag(
    dag_id="fuente_api_pipeline",
    schedule=None,  # manual por ahora; poner un cron (ej. "0 3 * * *") para que corra solo
    start_date=datetime.datetime(2026, 1, 1),
    catchup=False,
    tags=["fuente-api"],
)
def fuente_api_pipeline():
    @task
    def extract() -> str:
        """Extrae el pronóstico horario de Open-Meteo (api.open-meteo.com) —
        API pública real, sin API key ni registro. Coordenadas por defecto:
        Bogotá. Cambiar LAT/LON o pasarlas por variable de entorno si se
        quiere otra ciudad.
        """
        import requests
        from google.cloud import storage

        lat = os.environ.get("SOURCE_LAT", "4.7110")
        lon = os.environ.get("SOURCE_LON", "-74.0721")

        resp = requests.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": lat,
                "longitude": lon,
                "hourly": "temperature_2m,relative_humidity_2m,precipitation_probability",
                "forecast_days": 1,
                "timezone": "auto",
            },
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()

        hourly = data["hourly"]
        rows = [
            {
                "id": i,
                "source": SOURCE_NAME,
                "extracted_at": timestamp,
                "temperature_c": hourly["temperature_2m"][i],
                "humidity_pct": hourly["relative_humidity_2m"][i],
                "precip_probability_pct": hourly["precipitation_probability"][i],
            }
            for i, timestamp in enumerate(hourly["time"])
        ]

        ts = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
        blob_path = f"{SOURCE_NAME}/raw_{ts}.json"

        client = storage.Client()
        client.bucket(RAW_BUCKET).blob(blob_path).upload_from_string(
            "\n".join(json.dumps(r) for r in rows), content_type="application/json"
        )
        return blob_path

    @task
    def transform(raw_blob_path: str) -> str:
        import pandas as pd
        from google.cloud import storage

        client = storage.Client()
        lines = client.bucket(RAW_BUCKET).blob(raw_blob_path).download_as_text().splitlines()
        rows = [json.loads(line) for line in lines if line.strip()]

        df = pd.DataFrame(rows)
        df["processed_at"] = datetime.datetime.utcnow().isoformat()

        ts = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
        stage_blob_path = f"{SOURCE_NAME}/stage_{ts}.parquet"

        buf = io.BytesIO()
        df.to_parquet(buf, index=False)
        client.bucket(STAGE_BUCKET).blob(stage_blob_path).upload_from_string(
            buf.getvalue(), content_type="application/octet-stream"
        )
        return stage_blob_path

    @task
    def load(stage_blob_path: str) -> None:
        import pandas as pd
        from google.cloud import bigquery, storage

        client = storage.Client()
        local_path = "/tmp/fuente_api_stage.parquet"
        client.bucket(STAGE_BUCKET).blob(stage_blob_path).download_to_filename(local_path)
        df = pd.read_parquet(local_path)

        bq_client = bigquery.Client(project=PROJECT_ID)
        table_id = f"{PROJECT_ID}.{BQ_DATASET}.fuente_api"

        job = bq_client.load_table_from_dataframe(
            df,
            table_id,
            job_config=bigquery.LoadJobConfig(write_disposition="WRITE_APPEND"),
        )
        job.result()

    load(transform(extract()))


fuente_api_pipeline()
