# Infra

Shared cluster infrastructure for my pet projects, as Kubernetes manifests for a
single-node **k3s** cluster. Smallest thing that works, with all the necessary pieces —
no over-engineering.

This repo owns **shared infrastructure only**: the `infra` namespace, MongoDB,
monitoring (Grafana, Telegraf), backups, the maintenance page, and the shared
cert-manager issuer. Applications (cv, nest2d, mixdrinks, ypod, velonuxt, …) live in
their own repos and carry their own manifests, including their own ingress.

> Migrated from Docker Swarm. The requirements the old stack encoded are preserved in
> [`docs/migration-requirements.md`](docs/migration-requirements.md).

## What runs here

| Component | Kind | Notes |
|---|---|---|
| MongoDB | StatefulSet + headless Service | replica set `rs0`, single node, auth + keyfile |
| Mongo RS init | Job | runs `rs.initiate` automatically (idempotent) |
| Grafana | Deployment + PVC + Service + Ingress | `grafana.stelmashchuk.dev`, mongodb datasource |
| Telegraf | DaemonSet | host metrics → Mongo `vps_metrics` |
| compass-web | Deployment + Service + Ingress | `compass.stelmashchuk.dev`, Mongo web viewer |
| maintenance | Deployment + Service + Ingress | `maintenance.stelmashchuk.dev`, static page |
| Mongo backups | CronJobs (daily, weekly) | `mongodump` → S3 |
| Grafana backup | CronJob (daily) | `grafana.db` → S3 |
| cert-manager issuer | ClusterIssuer | Let's Encrypt via Traefik HTTP-01 |

Ingress is **Traefik** (built into k3s); TLS is **cert-manager** + Let's Encrypt.
Storage is the built-in **local-path** StorageClass.

## Layout

```
namespaces/                  the `infra` namespace
mongo/                       StatefulSet, headless Service, rs-init Job
monitoring/grafana/          Dockerfile (plugin baked in) + manifests
monitoring/telegraf/         telegraf.conf + DaemonSet (ConfigMap generated in CI)
backups/mongo/               backup image + daily/weekly CronJobs
backups/grafana/             backup image + daily CronJob
tools/compass-web/           Mongo web viewer
tools/maintenance/           static maintenance page
bootstrap/                   one-time cluster setup (docs) + cert-manager issuer
docs/                        migration notes
.github/workflows/deploy.yml build images → GHCR, then kubectl apply on push to main
```

Raw YAML for now; Kustomize (`kubectl apply -k`) will be introduced only if/when
repetition warrants it. Not Helm.

## Deploy

Push to `main`. The [deploy workflow](.github/workflows/deploy.yml):
1. builds the custom images (`grafana`, `mongo-rs-backup`, `grafana-backup`) and pushes
   them to GHCR tagged with the commit SHA;
2. authenticates to the cluster with the base64 `KUBE_CONFIG` secret;
3. pins the manifests' `:latest` GHCR references to the built SHA;
4. creates the namespace, generates the Telegraf ConfigMap from `telegraf.conf`, and
   `kubectl apply`s everything.

First-time cluster setup (k3s install, kubeconfig export, firewall, cert-manager) is in
[`bootstrap/README.md`](bootstrap/README.md).

## Secrets

The shared `secret` is dynamically generated during the GitHub Action CI from GitHub Secrets.
You must configure the following secrets in your GitHub Repository Settings:
- `USERNAME`
- `PASSWORD`
- `MONGO_RS_KEYFILE_CONTENT` (generate locally once via `openssl rand -base64 756`)
- `S3_ENDPOINT`
- `S3_BUCKET`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `KUBE_CONFIG` (base64 encoded admin kubeconfig)

## Manual / one-time steps

- **Cluster bootstrap** — see [`bootstrap/README.md`](bootstrap/README.md): k3s install,
  kubeconfig → `KUBE_CONFIG`, Hetzner firewall, cert-manager install.
- **Secrets** — Set up the required GitHub Secrets in your repository.
- That's it. The replica set is initiated automatically by the `mongo-rs-init` Job; no
  manual `rs.initiate`.

## Restore from backup

Backups are gzip archives in S3 (`mongo-rs-daily`, `mongo-rs-weekly`, `grafana-daily`).

```sh
# Mongo: restore a dump into the cluster (run from a machine with the connection URI).
mongorestore --uri="mongodb://<user>:<pass>@<host>:27017/?replicaSet=rs0&authSource=admin" \
  --drop --gzip --archive=mongodump-2026-06-13_03-30.gz
```

## Security TODOs

Tracked, deliberately deferred (no over-engineering):
- [ ] **Hetzner firewall** — restrict `:6443` (and `:22`) to known sources.
- [ ] **Scoped deploy creds** — replace the admin `KUBE_CONFIG` with a ServiceAccount +
      RBAC limited to the `infra` namespace.
- [ ] **sealed-secrets** — move secret material into git, encrypted.
