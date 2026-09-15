"""DAG de ejemplo para fuente-api: extrae el pronóstico del clima de
Open-Meteo, transforma y carga a BigQuery.

Este archivo define SOLO el DAG (el orden y las dependencias entre
tareas) — la lógica real de cada etapa vive en tasks.py, subido junto a
este archivo a la misma carpeta dags/ del bucket de Composer (ver
infra/main.tf, dos instancias del módulo composer-dag). Airflow lo recoge
todo automáticamente, sin necesidad de reiniciar nada.

A diferencia de fuente-postgres/fuente-sqlserver (3 Cloud Run Jobs
independientes, sin orquestación automática entre ellos), acá Airflow SÍ
controla el orden y las dependencias explícitas entre etapas — el caso
típico donde Composer/Airflow tiene sentido frente a jobs sueltos.

Variables de entorno esperadas (inyectadas al entorno completo de Composer,
ver infra/main.tf): RAW_BUCKET, STAGE_BUCKET, BQ_PROJECT_ID, BQ_DATASET.
("PROJECT_ID" a secas está reservado por Composer y no se puede
sobrescribir como variable de entorno propia.)
Opcionales: SOURCE_LAT, SOURCE_LON (default: Bogotá).
"""

from __future__ import annotations

import datetime
import os

from airflow.decorators import dag, task

import tasks

RAW_BUCKET = os.environ["RAW_BUCKET"]
STAGE_BUCKET = os.environ["STAGE_BUCKET"]
PROJECT_ID = os.environ["BQ_PROJECT_ID"]
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
        return tasks.extract(RAW_BUCKET)

    @task
    def transform(raw_blob_path: str) -> str:
        return tasks.transform(RAW_BUCKET, STAGE_BUCKET, raw_blob_path)

    @task
    def load(stage_blob_path: str) -> None:
        tasks.load(STAGE_BUCKET, PROJECT_ID, BQ_DATASET, stage_blob_path)

    load(transform(extract()))


fuente_api_pipeline()
