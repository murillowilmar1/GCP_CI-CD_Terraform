# Runbook: armar este laboratorio desde cero

Guía paso a paso para replicar todo este setup en un par de proyectos GCP
nuevos (o para reconstruirlo si algo se borra). Está pensada para seguirse
en orden, de arriba hacia abajo, sin dar nada por sabido.

El código de este repo **ya tiene** todos los permisos y fixes que se
descubrieron la primera vez que se aplicó esto de verdad (ver sección
"Errores que ya no deberías ver" al final) — así que siguiendo esta guía
con el código tal cual está, no deberías repetir esos problemas. Los pasos
que siguen siendo manuales de verdad (no se pueden poner en Terraform) están
marcados con **⚠️ manual**.

---

## 0. Qué necesitás antes de empezar

- Dos proyectos de GCP ya creados (uno para dev, otro para prod), con
  facturación habilitada.
- Una cuenta de Google con rol **Owner** en ambos proyectos.
- Un repositorio de GitHub vacío (o con este código) donde vas a trabajar.
- Acceso a una terminal: puede ser **Cloud Shell** (más simple, no instala
  nada local) o tu propia máquina.

---

## 1. Instalar herramientas (si usás tu propia máquina)

Si usás Cloud Shell, saltate este paso — ya viene con `gcloud`. Terraform
sí hay que instalarlo incluso en Cloud Shell.

### gcloud (solo si NO usás Cloud Shell)

- Windows: `winget install --id Google.CloudSDK -e`
- Mac/Linux: ver https://cloud.google.com/sdk/docs/install

### Terraform (Cloud Shell y máquina propia por igual)

```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
terraform version   # confirmar que funciona
```

> Si en Cloud Shell `terraform version` sigue mostrando un mensaje de "no
> instalado" después de instalarlo, corré `hash -r` — es una caché de rutas
> de bash desactualizada, no que falló la instalación.

### Autenticar gcloud (⚠️ manual — abre navegador)

```bash
gcloud auth login
gcloud auth application-default login
```

El segundo comando es el que necesita Terraform para autenticarse — sin
él, `terraform plan/apply` falla aunque `gcloud` funcione bien.

---

## 2. Preparar el repositorio de GitHub

```bash
git clone <URL-de-tu-repo> multi-fuente-demo-gcp
cd multi-fuente-demo-gcp
# copiar/pegar todo el código de este proyecto acá si el repo está vacío
git checkout -b dev
git add -A
git commit -m "Initial commit"
git push origin dev
git push origin dev:main   # main arranca igual que dev
```

Necesitás las dos ramas: `dev` (donde se trabaja el día a día) y `main`
(donde vive lo que está en prod).

---

## 3. Editar `env/dev.tfvars` y `env/prod.tfvars`

Poner ahí los `project_id` reales de tus dos proyectos, y elegir un
`name_prefix` corto (máx. ~20 caracteres) para cada uno — se usa para
nombrar buckets globalmente únicos. Ejemplo:

```hcl
# env/dev.tfvars
project_id  = "tu-proyecto-dev"
name_prefix = "tuempresa-dev"
region      = "us-central1"
environment = "dev"
```

---

## 4. Bootstrap: crear los buckets de tfstate (⚠️ manual)

El backend `gcs` de Terraform necesita que el bucket ya exista antes de
`terraform init` — no puede crearlo con el propio Terraform que lo va a
usar como backend. Correr en cada proyecto:

```bash
# DEV
gcloud config set project <tu-proyecto-dev>
gcloud services enable storage.googleapis.com --project=<tu-proyecto-dev>
gcloud storage buckets create gs://<name_prefix_dev>-tfstate \
  --project=<tu-proyecto-dev> --location=us-central1 --uniform-bucket-level-access
gcloud storage buckets update gs://<name_prefix_dev>-tfstate --versioning

# PROD (repetir con el proyecto de prod)
gcloud config set project <tu-proyecto-prod>
gcloud services enable storage.googleapis.com --project=<tu-proyecto-prod>
gcloud storage buckets create gs://<name_prefix_prod>-tfstate \
  --project=<tu-proyecto-prod> --location=us-central1 --uniform-bucket-level-access
gcloud storage buckets update gs://<name_prefix_prod>-tfstate --versioning
```

Si el nombre de bucket que elegiste ya está tomado por otra cuenta en todo
GCP (los nombres de bucket son globales), vas a tener que cambiar el
`name_prefix` y actualizar `env/*.tfvars` de nuevo.

---

## 5. Desplegar `platform-shared` (dev primero, después prod)

```bash
scripts/tf.sh platform-shared dev init
scripts/tf.sh platform-shared dev plan     # revisar antes de aplicar
scripts/tf.sh platform-shared dev apply
```

Esto crea: buckets raw/stage/analytics/query-results, el dataset de
BigQuery, la service account compartida de pipelines, el repo de Artifact
Registry, y habilita ~13 APIs del proyecto (incluida `compute.googleapis.com`
y `secretmanager.googleapis.com`, necesarias más adelante).

Repetir exactamente igual para prod:

```bash
scripts/tf.sh platform-shared prod init
scripts/tf.sh platform-shared prod plan
scripts/tf.sh platform-shared prod apply
```

---

## 6. Desplegar `cicd` (dev) — acá se conecta GitHub

```bash
scripts/tf.sh cicd dev init
scripts/tf.sh cicd dev apply
```

### 6.1 Autorizar GitHub (⚠️ manual, dos pasos, inherente al producto)

Este primer `apply` crea la conexión de Developer Connect pero queda en
estado `PENDING_USER_OAUTH` — Terraform no puede completar un login de
GitHub por vos. Conseguir el link de autorización:

```bash
cd cicd
terraform output developer_connect_installation_state
cd ..
```

Copiar el `action_uri` que aparece ahí, abrirlo en el navegador (logueado
con la cuenta que va a administrar esto), autorizar la GitHub App e
instalarla sobre tu repositorio.

### 6.2 Terminar de aplicar

```bash
scripts/tf.sh cicd dev apply
```

Ahora sí crea el `git_repository_link` y los triggers de dev (uno por
fuente, definidos en `cicd/variables.tf` → `var.fuentes`).

> **Si este segundo apply falla** con algo como `service account ... does
> not exist` sobre el service agent de Developer Connect
> (`service-<NUM>@gcp-sa-devconnect...`) o sobre la SA default de Compute:
> es una carrera de creación asíncrona (la cuenta se crea como efecto
> secundario de un paso anterior y puede tardar unos segundos en aparecer).
> Simplemente correr el mismo `apply` una vez más.

### 6.3 Vos (el operador) necesitás un permiso extra (⚠️ manual)

Para poder crear/administrar los triggers que usan la service account
`cicd-terraform-dev`, tu propia cuenta necesita `iam.serviceAccountUser`
sobre esa SA específica (ser Owner del proyecto no alcanza para esta
validación puntual de Cloud Build):

```bash
gcloud iam service-accounts add-iam-policy-binding \
  cicd-terraform-dev@<tu-proyecto-dev>.iam.gserviceaccount.com \
  --member="user:<tu-email>" \
  --role="roles/iam.serviceAccountUser" \
  --project=<tu-proyecto-dev>
```

Si el `apply` del paso 6.2 falla con `insufficient permissions from
service account ... to project ...`, es este permiso el que falta —
corré el comando de arriba y repetí el `apply`.

### 6.4 Verificar

`console.cloud.google.com/cloud-build/triggers?project=<tu-proyecto-dev>`
debería mostrar un trigger `dev-<fuente>` por cada fuente en
`cicd/variables.tf`.

---

## 7. Probar el flujo de dev

```bash
git checkout dev
# editar algo en fuentes/<alguna-fuente>/**
git add fuentes/<alguna-fuente>
git commit -m "test"
git push origin dev
```

Se dispara solo el trigger de esa fuente. Seguir en
`console.cloud.google.com/cloud-build/builds?project=<tu-proyecto-dev>`.

Para correr un job y ver datos reales:

```bash
gcloud run jobs execute <fuente>-raw --region=us-central1 --project=<tu-proyecto-dev> --wait
gcloud run jobs execute <fuente>-stage --region=us-central1 --project=<tu-proyecto-dev> --wait
gcloud run jobs execute <fuente>-analytics --region=us-central1 --project=<tu-proyecto-dev> --wait
```

---

## 8. Repetir para prod: `cicd-prod`

Mismo patrón que el paso 6, pero contra el proyecto de prod y con
`cicd-prod` en vez de `cicd`:

```bash
scripts/tf.sh cicd-prod prod init
scripts/tf.sh cicd-prod prod apply
# -> PENDING_USER_OAUTH, conseguir el link:
cd cicd-prod && terraform output developer_connect_installation_state && cd ..
# abrir el link, autorizar, y:
scripts/tf.sh cicd-prod prod apply

# permiso del operador sobre la SA de prod:
gcloud iam service-accounts add-iam-policy-binding \
  cicd-terraform-prod@<tu-proyecto-prod>.iam.gserviceaccount.com \
  --member="user:<tu-email>" \
  --role="roles/iam.serviceAccountUser" \
  --project=<tu-proyecto-prod>
```

Verificar en `console.cloud.google.com/cloud-build/triggers?project=<tu-proyecto-prod>`:
deberían existir **2** triggers, `promote-plan` y `promote-apply` (no uno
por fuente — es el pipeline paramétrico).

---

## 9. Promover una fuente a prod

### 9.1 Sincronizar el código (⚠️ manual, a propósito)

```bash
git checkout main
git pull origin main
git checkout dev -- fuentes/<fuente>   # sync acotado, solo esa carpeta
git commit -m "promote: <fuente> a prod"
git push origin main
```

### 9.2 Correr el plan

Por consola: `Cloud Build → Activadores (Triggers)` en el proyecto de
prod → botón **"Ejecutar"** en la fila de `promote-plan` → en el panel que
se abre, poner la rama `main` y la variable `_FUENTE` = nombre de la
fuente (ej. `fuente-postgres`) → Ejecutar.

O por CLI:

```bash
gcloud builds triggers run promote-plan \
  --project=<tu-proyecto-prod> --region=us-central1 \
  --branch=main --substitutions=_FUENTE=<fuente>
```

### 9.3 Revisar el diff

```bash
gcloud storage cat gs://<name_prefix_prod>-tfstate/cicd-prod-plans/<fuente>/tfplan.txt
```

### 9.4 Correr el apply y aprobar (⚠️ manual, a propósito — es el gate de prod)

```bash
gcloud builds triggers run promote-apply \
  --project=<tu-proyecto-prod> --region=us-central1 \
  --branch=main --substitutions=_FUENTE=<fuente>
```

Esto queda pausado esperando aprobación. Aprobar desde
`Cloud Build → Historial` (botón "Aprobar" en el build), o:

```bash
gcloud builds approve <BUILD_ID> --project=<tu-proyecto-prod>
```

---

## 10. (Opcional) Activar `fuente-api` (Cloud Composer)

**Antes de hacerlo**: un entorno de Composer corre 24/7 y genera costo
continuo (no es serverless como el resto de este laboratorio), y tarda
**20 a 50+ minutos** en crearse — mucho más lento que cualquier otra cosa
en este repo. Además, si falta el permiso `roles/composer.worker` (ver
abajo), el error recién aparece **después de ~50 minutos**, no al
principio — es, por lejos, la parte más lenta de iterar en todo este
laboratorio.

```bash
scripts/tf.sh cicd dev apply   # crea el trigger dev-fuente-api
```

Después, cualquier push a `fuentes/fuente-api/**` dispara el pipeline que
crea el entorno de Composer real y sube el DAG.

**El código de `platform-shared/main.tf` ya incluye todos los permisos que
Composer necesita** (se descubrieron uno por uno la primera vez, cada
descubrimiento costando una espera larga — ver tabla de errores abajo).
Si estás reconstruyendo esto en un proyecto nuevo, esos permisos ya están
en el código, no hace falta agregarlos a mano.

### Apagar todo al terminar la práctica

```bash
scripts/tf.sh fuentes/fuente-api/infra dev destroy
```

Esto destruye el entorno de Composer (deja de generar costo) y el DAG
subido. El trigger `dev-fuente-api` en sí no cuesta nada, se puede dejar
o sacarlo de `cicd/variables.tf` → `var.fuentes` y volver a aplicar `cicd`.

---

## Errores que ya no deberías ver (pero por qué existen, si aparecen)

Estos ya están resueltos en el código de este repo. Se documentan acá por
si algo se revierte sin querer, o si estás mirando este runbook mientras
escribís algo parecido desde cero.

| Error | Causa | Dónde está el fix |
|---|---|---|
| `could not create a secret: permission_denied` al autorizar GitHub | Faltaba `roles/secretmanager.admin` para el service agent de Developer Connect, y/o la API de Secret Manager sin habilitar | `platform-shared/main.tf` (API) + `cicd*/main.tf` (permiso) |
| `insufficient permissions from service account ... to project ...` al crear un trigger | Faltaban `roles/cloudbuild.builds.builder` y `roles/developerconnect.readTokenAccessor` en la SA custom, y/o `roles/iam.serviceAccountUser` del operador sobre esa SA | `cicd*/main.tf` + comando manual (pasos 6.3/8) |
| `key in the template "X" is not a valid built-in substitution` en un build | Variables de bash locales sin escapar (`$VAR` en vez de `$$VAR`) en un `cloudbuild.yaml` — Cloud Build intenta resolver CUALQUIER `$VAR` como substitution propia | Todos los `cloudbuild*.yaml` del repo |
| `gcloud: command not found` en un step de Cloud Build | La imagen `gcr.io/cloud-builders/docker` no trae `gcloud` instalado | Los `cloudbuild*.yaml` sacan el digest de la salida de `docker push`, no de `gcloud artifacts describe` |
| `missing permission on the build service account` al desplegar una Cloud Function | La organización tiene deshabilitado el otorgamiento automático de roles a la SA default de Compute, y esa SA no tiene ningún permiso | `platform-shared/main.tf` (grants explícitos + habilita `compute.googleapis.com`) |
| `Service account ...-compute@developer.gserviceaccount.com does not exist` | La SA default de Compute no existe hasta que se habilita `compute.googleapis.com` en el proyecto | `platform-shared/main.tf` (ya en `required_apis`) |
| `Service account ...@gcp-sa-devconnect... does not exist` al aplicar `cicd`/`cicd-prod` en un proyecto nuevo | Ese service agent se crea recién como efecto secundario de la PRIMERA conexión de Developer Connect, no de habilitar la API sola — dependencia circular si el permiso depende de la conexión y la conexión depende del permiso | Se sacó el `depends_on` en `cicd*/main.tf`; si aparece este error, correr el `apply` una segunda vez alcanza |
| `Environment variables [PROJECT_ID] may not be overridden` al crear un entorno de Composer | `PROJECT_ID` está reservado por Composer, no se puede usar como nombre de variable de entorno propia en `software_config.env_variables` | Renombrado a `BQ_PROJECT_ID` en `fuentes/fuente-api/infra/main.tf` y `src/dag.py` |
| `missing required permissions: iam.serviceAccounts.getIamPolicy, setIamPolicy` al crear un entorno de Composer | Al service agent de Composer (`service-<NUM>@cloudcomposer-accounts.iam.gserviceaccount.com`) le falta `roles/composer.ServiceAgentV2Ext` | `platform-shared/main.tf` |
| `Please enable all APIs Cloud Composer depends on: [container.googleapis.com]` | Composer 2 corre sobre GKE por detrás; falta esa API habilitada | `platform-shared/main.tf` (ya en `required_apis`) |
| `Failed to create environment, but no error was surfaced... missing role roles/composer.worker` (aparece recién después de ~50 min) | La service account usada como `node_config.service_account` del entorno (acá: `pipeline_sa`) no tiene `roles/composer.worker` | `platform-shared/main.tf` |
| El script `scripts/tf.sh` da "Permission denied" al clonar en Linux/Cloud Shell | Se perdió el bit ejecutable al versionar desde Windows | Ya corregido en el repo (`git update-index --chmod=+x`); si vuelve a pasar: `chmod +x scripts/tf.sh` |
