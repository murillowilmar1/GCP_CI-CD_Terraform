# Dockerfile genérico reusado por TODOS los jobs de TODAS las fuentes
# (raw/stage/analytics). El build context es la carpeta de la etapa
# específica (ej. fuentes/fuente-postgres/src/raw/), que debe traer su
# propio job.py + requirements.txt.
#
# Build (ver fuentes/<fuente>/cloudbuild.yaml):
#   docker build -f docker/job.Dockerfile -t <tag> fuentes/<fuente>/src/<stage>

FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY job.py .

ENTRYPOINT ["python", "job.py"]
