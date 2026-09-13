# multi-fuente-demo-gcp

Laboratorio de CI/CD con Terraform en GCP, equivalente al que ya existe en
AWS (CodePipeline/CodeBuild/Glue/S3/Athena), adaptado a servicios nativos de
Google Cloud:

| AWS | GCP (este repo) |
|---|---|
| CodePipeline + CodeBuild | Cloud Build (triggers, 2da gen, vía Developer Connect) |
| S3 | Cloud Storage (GCS) |
| Glue Catalog + Athena | BigQuery (dataset + motor de consulta, un solo servicio) |
| Glue Jobs | Cloud Run Jobs (`modules/cloud-run-job`) |
| Lambda | Cloud Functions 2nd gen (`modules/cloud-function`) |
| Cuentas AWS separadas (dev/prod) | Proyectos GCP separados: `lakehouse-adventureworks-dev` / `-prod` |
| Aprobación manual de CodePipeline | `approval_config` nativo de Cloud Build |

## Arquitectura (resumen)

- **`platform-shared/`**: buckets raw/stage/analytics, dataset BigQuery
  (catálogo), service account compartida, repo de Artifact Registry. Una
  copia por proyecto (dev y prod).
- **`cicd/`**: conexión a GitHub (Developer Connect) + un trigger de Cloud
  Build por fuente. Push a la rama `dev` que toque `fuentes/<fuente>/**` →
  build automático (sin aprobación) que hace `terraform plan` + `apply` de
  esa fuente. Solo existe en el proyecto **dev**.
- **`cicd-prod/`**: misma conexión a GitHub pero en el proyecto **prod** +
  UN pipeline paramétrico (no uno por fuente): dos triggers manuales,
  `promote-plan` y `promote-apply`, invocados con
  `--substitutions=_FUENTE=<fuente>`. `promote-apply` requiere aprobación
  manual (`approval_config.approval_required = true`) antes de ejecutar.
- **`fuentes/<fuente>/`**: código de cada fuente (`src/raw`, `src/stage`,
  `src/analytics`, cada uno con su `job.py` + `requirements.txt`, empaquetado
  como imagen de contenedor) y su infraestructura (`infra/`, que instancia 3
  Cloud Run Jobs vía `modules/cloud-run-job` y lee `platform-shared` por
  `terraform_remote_state`). `fuente-sqlserver` además tiene `src/audit`
  (Cloud Function) y una tabla BigQuery `audit_log`.
- **`modules/`**: código propio y autocontenido — `cloudbuild-pipeline`
  (triggers), `cloud-run-job` (jobs de procesamiento), `cloud-function`
  (funciones).
- **`docker/job.Dockerfile`**: Dockerfile genérico reusado por todas las
  etapas de todas las fuentes (build context = la carpeta de esa etapa).

## Prerrequisitos

- `terraform` >= 1.5 instalado localmente (o correr todo desde Cloud Shell).
- `gcloud` autenticado con permisos de owner/editor en ambos proyectos
  (`lakehouse-adventureworks-dev`, `lakehouse-adventureworks-prod`). Cloud
  Shell ya viene con esto listo.
- Acceso al repo `https://github.com/murillowilmar1/GCP_CI-CD_Terraform`.

## 1. Bootstrap (una sola vez, a mano)

El backend `gcs` de Terraform necesita que el bucket de tfstate ya exista
antes de poder hacer `terraform init` — no puede crearlo con el propio
Terraform que lo va a usar como backend. Correr en Cloud Shell:

```bash
# --- DEV ---
gcloud config set project lakehouse-adventureworks-dev
gcloud services enable storage.googleapis.com --project=lakehouse-adventureworks-dev
gcloud storage buckets create gs://lakehouse-aw-dev-tfstate \
  --project=lakehouse-adventureworks-dev --location=us-central1 --uniform-bucket-level-access
gcloud storage buckets update gs://lakehouse-aw-dev-tfstate --versioning

# --- PROD ---
gcloud config set project lakehouse-adventureworks-prod
gcloud services enable storage.googleapis.com --project=lakehouse-adventureworks-prod
gcloud storage buckets create gs://lakehouse-aw-prod-tfstate \
  --project=lakehouse-adventureworks-prod --location=us-central1 --uniform-bucket-level-access
gcloud storage buckets update gs://lakehouse-aw-prod-tfstate --versioning
```

## 2. Desplegar dev

```bash
# 2.1 Plataforma compartida (buckets, BigQuery, SA, Artifact Registry)
scripts/tf.sh platform-shared dev init
scripts/tf.sh platform-shared dev apply

# 2.2 CI/CD de dev (conexión a GitHub + triggers por fuente)
scripts/tf.sh cicd dev init
scripts/tf.sh cicd dev apply
```

El primer `apply` de `cicd` crea la conexión a GitHub en estado
`PENDING_USER_OAUTH`. Hay que completarlo a mano (no se puede automatizar,
requiere autorizar en el navegador):

```bash
cd cicd
terraform output developer_connect_installation_state
# abrir el "action_uri" que aparece ahí, autorizar la GitHub App e
# instalarla sobre el repo GCP_CI-CD_Terraform
cd ..
scripts/tf.sh cicd dev apply   # ahora sí crea el git_repository_link y los triggers
```

Verificar en el portal: Cloud Build → Triggers
(`console.cloud.google.com/cloud-build/triggers?project=lakehouse-adventureworks-dev`)
deberían aparecer `dev-fuente-postgres` y `dev-fuente-sqlserver`.

## 3. Probar el flujo de dev

```bash
git checkout -b dev   # si no existe todavía
git add fuentes/fuente-postgres
git commit -m "test: dispara pipeline de dev de fuente-postgres"
git push origin dev
```

Como el push toca `fuentes/fuente-postgres/**`, solo se dispara
`dev-fuente-postgres` (no `dev-fuente-sqlserver`). Se puede seguir el build
en Cloud Build → History. El build: construye y sube las 3 imágenes,
corre `terraform plan` + `apply` → quedan 3 Cloud Run Jobs creados en dev.

Para correr un job manualmente y ver el resultado:

```bash
gcloud run jobs execute fuente-postgres-raw --region=us-central1 --project=lakehouse-adventureworks-dev
gcloud run jobs execute fuente-postgres-stage --region=us-central1 --project=lakehouse-adventureworks-dev
gcloud run jobs execute fuente-postgres-analytics --region=us-central1 --project=lakehouse-adventureworks-dev
```

Después de correr los 3 en orden, la tabla
`multifuente_catalog.fuente_postgres` en BigQuery (proyecto dev) debería
tener 10 filas.

## 4. Desplegar prod

Mismo patrón que dev, pero contra el proyecto prod:

```bash
scripts/tf.sh platform-shared prod init
scripts/tf.sh platform-shared prod apply

scripts/tf.sh cicd-prod prod init
scripts/tf.sh cicd-prod prod apply
# -> PENDING_USER_OAUTH, abrir action_uri, autorizar, y volver a aplicar:
cd cicd-prod && terraform output developer_connect_installation_state && cd ..
scripts/tf.sh cicd-prod prod apply
```

## 5. Promover una fuente a prod

```bash
# 5.1 Sync acotado de la carpeta de esa fuente, dev -> main
git checkout main
git checkout dev -- fuentes/fuente-postgres
git commit -m "promote: fuente-postgres a prod"
git push origin main

# 5.2 Plan (revisar el diff antes de aprobar nada)
gcloud builds triggers run promote-plan \
  --project=lakehouse-adventureworks-prod --region=us-central1 \
  --branch=main --substitutions=_FUENTE=fuente-postgres

# leer el diff:
gcloud storage cat gs://lakehouse-aw-prod-tfstate/cicd-prod-plans/fuente-postgres/tfplan.txt

# 5.3 Apply (queda pausado esperando aprobación)
gcloud builds triggers run promote-apply \
  --project=lakehouse-adventureworks-prod --region=us-central1 \
  --branch=main --substitutions=_FUENTE=fuente-postgres

# aprobar (ver el build ID en Cloud Build -> History, estado "Approval pending"):
gcloud builds approve <BUILD_ID> --project=lakehouse-adventureworks-prod
```

## Cosas a tener en cuenta

- **`env/dev.tfvars` y `env/prod.tfvars` son compartidos por todas las
  capas.** Algunas capas (`cicd`, `cicd-prod`) no usan todas las claves —
  Terraform tira un *warning* de "undeclared variable", no un error; es
  esperado, se puede ignorar.
- **El trigger `manual` (usado en `cicd-prod`) usa un truco**: un
  `included_files` que apunta a una ruta que nunca existe en un commit real,
  para que el webhook de GitHub jamás lo dispare solo, pero siga siendo
  invocable a mano. No se pudo probar contra un proyecto real durante el
  desarrollo — si `gcloud builds triggers run promote-plan ...` no funciona
  como se espera, ese es el primer lugar a revisar.
- Las imágenes de los jobs se referencian **por digest**, no por tag
  (`imagen@sha256:...`), para que Terraform detecte el cambio y actualice el
  Cloud Run Job en cada build — si se usara `:latest`, Terraform no vería
  diferencia entre builds y el job nunca se actualizaría.
- Los `job.py` de `raw` generan datos sintéticos (no hay una base
  Postgres/SQL Server real conectada) — el `TODO` en cada archivo marca
  dónde iría la extracción real (`psycopg2`/`pyodbc`).
- `roles/editor` en las service accounts de CI/CD es deliberadamente amplio
  para un laboratorio; en un entorno con compliance estricto conviene
  reemplazarlo por un rol custom acotado.
