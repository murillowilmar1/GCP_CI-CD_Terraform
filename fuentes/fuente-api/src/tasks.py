"""Lógica real de las etapas del pipeline de fuente-api (extract/transform/
load), separada de la definición del DAG (dag.py) para que ese archivo se
quede enfocado solo en el orden y las dependencias entre tareas.

Este archivo se sube a la MISMA carpeta dags/ del bucket de Composer que
dag.py (ver infra/main.tf) — Airflow no lo trata como un DAG porque no
define ningún objeto `@dag` a nivel de módulo, así que dag.py lo puede
importar como un módulo Python normal (están en el mismo directorio).

Los imports de librerías pesadas (requests, pandas, google-cloud-*) van
DENTRO de cada función, no al principio del archivo: Airflow re-parsea
todos los DAGs periódicamente para detectar cambios, así que importar cosas
pesadas a nivel de módulo hace más lento ese parseo constante.
"""

import datetime
import io
import json
import os

SOURCE_NAME = "fuente-api"


def extract(raw_bucket: str) -> str:
    """Extrae el pronóstico horario de Open-Meteo (api.open-meteo.com) —
    API pública real, sin API key ni registro. Coordenadas por defecto:
    Bogotá. Cambiar SOURCE_LAT/SOURCE_LON (variables de entorno) para otra
    ciudad.

    Guarda la respuesta de la API TAL CUAL la devuelve (sin parsear ni
    reformatear nada) — ese es el contrato de la capa raw: una copia fiel
    de lo que entregó la fuente, para poder reprocesar después sin
    depender de la API si cambia o deja de estar disponible.
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

    ts = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
    blob_path = f"{SOURCE_NAME}/raw_{ts}.json"

    client = storage.Client()
    client.bucket(raw_bucket).blob(blob_path).upload_from_string(
        resp.text, content_type="application/json"
    )
    return blob_path


def transform(raw_bucket: str, stage_bucket: str, raw_blob_path: str) -> str:
    """Acá pasa la estructuración real: Open-Meteo devuelve los campos como
    listas paralelas (data["hourly"]["temperature_2m"][i] va con
    data["hourly"]["time"][i], etc.) — se "pivotea" eso a filas de una
    tabla (una fila por hora, con sus columnas), que es el formato que
    después carga BigQuery.
    """
    import pandas as pd
    from google.cloud import storage

    client = storage.Client()
    raw_text = client.bucket(raw_bucket).blob(raw_blob_path).download_as_text()
    data = json.loads(raw_text)

    hourly = data["hourly"]
    rows = [
        {
            "id": i,
            "source": SOURCE_NAME,
            "forecast_time": timestamp,
            "temperature_c": hourly["temperature_2m"][i],
            "humidity_pct": hourly["relative_humidity_2m"][i],
            "precip_probability_pct": hourly["precipitation_probability"][i],
        }
        for i, timestamp in enumerate(hourly["time"])
    ]

    df = pd.DataFrame(rows)
    df["processed_at"] = datetime.datetime.utcnow().isoformat()

    ts = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
    stage_blob_path = f"{SOURCE_NAME}/stage_{ts}.parquet"

    buf = io.BytesIO()
    df.to_parquet(buf, index=False)
    client.bucket(stage_bucket).blob(stage_blob_path).upload_from_string(
        buf.getvalue(), content_type="application/octet-stream"
    )
    return stage_blob_path


def load(stage_bucket: str, project_id: str, bq_dataset: str, stage_blob_path: str) -> None:
    import pandas as pd
    from google.cloud import bigquery, storage

    client = storage.Client()
    local_path = "/tmp/fuente_api_stage.parquet"
    client.bucket(stage_bucket).blob(stage_blob_path).download_to_filename(local_path)
    df = pd.read_parquet(local_path)

    bq_client = bigquery.Client(project=project_id)
    table_id = f"{project_id}.{bq_dataset}.fuente_api"

    job = bq_client.load_table_from_dataframe(
        df,
        table_id,
        job_config=bigquery.LoadJobConfig(write_disposition="WRITE_APPEND"),
    )
    job.result()
