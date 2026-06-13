# Extracted requirements (Docker Swarm → k3s)

This file records everything the old Docker Swarm stack encoded, captured **before**
deleting it, so no requirement is lost in the migration. Once the k3s manifests fully
cover these, this doc is historical reference.

Source files: `docker-stack.yml`, `docker-stack.local.yml`, `caddy/CaddyFile`,
`*-backup/backup.sh`, `telegraf/telegraf.conf`, `grafana/Dockerfile`, the two workflows.

---

## 1. Caddy reverse proxy → Traefik + cert-manager

Caddy handled auto-HTTPS (Let's Encrypt) and routing. ACME account email:
`vovochkastelmashchuk@gmail.com`. Certs were stored on disk (`/caddy_storage`) and
backed up to S3 — under k3s, cert-manager stores them as Kubernetes Secrets, so that
backup is dropped.

### Routes

| Host | Target (Swarm) | Owner after migration | Notes |
|---|---|---|---|
| `compass.stelmashchuk.dev` | `infra_mongo-rs-viewer:8080` | **this repo** | Mongo web viewer (compass-web) |
| `grafana.stelmashchuk.dev` | `infra_grafana:3000` | **this repo** | Grafana |
| `maintenance.stelmashchuk.dev` | static maintenance page | **this repo** | Maintenance fallback |
| `mixdrinks.org` | `mixdrinks_app:3000` | app repo | |
| `www.mixdrinks.org` | redirect → `https://mixdrinks.org{uri}` | app repo | |
| `stelmashchuk.dev` | `cv_app:3000` | app repo (cv) | |
| `nest2d.stelmashchuk.dev` | `nest2d_app:3000` | app repo (nest2d) | |
| `velonuxt.stelmashchuk.dev` | `velonuxt_app:3000` | app repo | sets `X-Real-IP` |
| `kickstart.stelmashchuk.dev` | redirect → `https://velonuxt.stelmashchuk.dev{uri}` | app repo | |
| `ypod.stelmashchuk.dev` | `ypod_app:3000` | app repo (ypod) | sets `X-Real-IP` |
| `hardandsoft.stelmashchuk.dev` | `ypod_app:3000` | app repo (ypod) | rewrites `/rss.xml` & `/files/rss.xml` → `/api/podcast/android-story/rss.xml`; sets `Host` + `X-Real-IP` |
| `podcast.stelmashchuk.dev` | `ypod_app:3000` | app repo (ypod) | sets `Host` + `X-Real-IP` |

**Decision:** app routes move to each app's own repo as `Ingress`/`IngressRoute`.
This repo only owns `compass`, `grafana`, and `maintenance` ingress, plus the
shared cert-manager `ClusterIssuer`.

App-side migration notes for the tricky routes (so they aren't forgotten when apps move):
- ypod's header rewrites and the rss path rewrites need Traefik middlewares
  (`replacePathRegex` / `headers`) in the app repo.
- `www.*` and `kickstart` redirects → Traefik `redirectregex` middleware in the app repo.

---

## 2. Backups → CronJobs

Old scheduler: `crazymax/swarm-cronjob:1.14.0` reading `swarm.cronjob.schedule` labels.
Replaced by native Kubernetes `CronJob`s (UTC; cluster `TZ=UTC`).

| Job | Schedule (cron) | When | S3 folder | Keep? |
|---|---|---|---|---|
| mongo daily | `30 3 * * *` | 03:30 daily | `mongo-rs-daily` | **yes → CronJob** |
| mongo weekly | `20 3 * * 2` | 03:20 Tuesdays | `mongo-rs-weekly` | **yes → CronJob** |
| grafana daily | `0 6 * * *` | 06:00 daily | `grafana-daily` | **yes → CronJob** |
| caddy daily | `0 5 * * *` | 05:00 daily | `caddy-daliy` *(typo in original)* | **dropped** (cert-manager owns certs) |
| node prune | `25 * * * *` | hourly | — | **dropped** (k8s image GC) |

(An hourly mongo backup existed previously; already removed in commit `605edf9`.)

### Backup targets / mechanics
- **S3-compatible** storage via `awscli` with a custom `--endpoint-url`.
- Bucket: `backups` (env `S3_BUCKET`). Endpoint/keys from secrets (see §4).
- **Mongo** (`mongo-rs-backup/backup.sh`): `mongodump --uri=$MONGO_URI --archive --gzip`
  → `s3://$S3_BUCKET/$S3_FOLDER/mongodump-<TS>.gz`. Image base `mongo:8.2.5` + awscli.
- **Grafana** (`grafana-backup/backup.sh`): `tar -czf` of `grafana.db`
  → `s3://$S3_BUCKET/$S3_FOLDER/grafana-backup-<TS>.tar.gz`. Base `ubuntu:22.04` + awscli.
  Needs the grafana data PVC mounted read access.
- Timestamp format: `date +'%Y-%m-%d_%H-%M'`.
- No retention/pruning logic on the bucket side (lifecycle policy is external, if any).

---

## 3. Image versions

| Component | Image | Fate |
|---|---|---|
| MongoDB | `mongo:8.2.3` | keep (StatefulSet) |
| Mongo backup base | `mongo:8.2.5` | keep (CronJob image) |
| Caddy | `caddy:2.11.1` | **removed** (Traefik built-in) |
| Grafana | `grafana/grafana:12.4.0-22081664032-ubuntu` | keep (Deployment) |
| Grafana mongodb datasource plugin | `haohanyang-mongodb-datasource` **v0.4.1** (unsigned) | keep |
| Telegraf | `telegraf:1.37.3` | keep (DaemonSet) |
| Mongo viewer | `haohanyang/compass-web:0.3.1` | keep (Deployment) |
| swarm-cronjob | `crazymax/swarm-cronjob:1.14.0` | **removed** (native CronJob) |
| node prune | `docker:27.3.1-cli` | **removed** |

---

## 4. Environment variables & secrets

All created out-of-band (`kubectl create secret`), never committed.

| Name | Used by | Purpose |
|---|---|---|
| `USERNAME` | mongo, grafana, compass, telegraf, backups | Mongo root user **and** Grafana admin user |
| `PASSWORD` | same | Mongo root password / Grafana admin password |
| `MONGO_RS_KEYFILE_CONTENT` | mongo | Replica-set internal-auth keyfile (`openssl rand -base64 756`) |
| `S3_ENDPOINT` | backups | S3-compatible endpoint URL |
| `S3_BUCKET` | backups | `backups` |
| `S3_ACCESS_KEY_ID` | backups | S3 access key |
| `S3_SECRET_ACCESS_KEY` | backups | S3 secret key |

Derived connection strings (built from the above, not stored separately):
- In-cluster Mongo URI (authenticated):
  `mongodb://$USERNAME:$PASSWORD@mongo-0.mongo.infra.svc.cluster.local:27017/?replicaSet=rs0&authSource=admin`
- Compass viewer also takes `CW_BASIC_AUTH_USERNAME`/`CW_BASIC_AUTH_PASSWORD` (= USERNAME/PASSWORD).

CI/CD secrets/vars (GitHub Actions): old SSH-based deploy used `ROOT_SSH_PRIVATE_KEY`,
`vars.HOST`, `vars.USERNAME`. **New** deploy needs only `KUBE_CONFIG` (base64 admin
kubeconfig, server line → public IP). GHCR push uses the built-in `GITHUB_TOKEN`.

---

## 5. MongoDB

- Replica set `rs0`, single member.
- Runs with `--replSet rs0 --keyFile <keyfile> --bind_ip_all` and **auth on from first boot**
  (root user via `MONGO_INITDB_ROOT_USERNAME/PASSWORD`).
- Keyfile must be mode `0400`, owned by uid/gid `999`. Swarm did this inline:
  `echo "$KEYFILE" > /data/keyfile && chmod 400 && chown 999:999 && docker-entrypoint.sh mongod ...`
  (container starts as root, entrypoint drops to the `mongodb` user). Reproduced in k8s
  via the same start command writing the keyfile from the Secret into an `emptyDir`.
- `rs.initiate` is run **automatically** (idempotent `try { rs.status() } catch { rs.initiate(...) }`),
  member host `mongo-0.mongo.infra.svc.cluster.local:27017`. No manual step.
- Data on a PVC (`local-path`). **No data migration** — fresh VM, fresh volume.

---

## 6. Grafana

- Image `grafana/grafana:12.4.0-22081664032-ubuntu` with the unsigned
  `haohanyang-mongodb-datasource` v0.4.1 plugin baked in
  (`GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=haohanyang-mongodb-datasource`).
- Env: `GF_SECURITY_ADMIN_USER`/`GF_SECURITY_ADMIN_PASSWORD` (= USERNAME/PASSWORD),
  `GF_SERVER_ROOT_URL=https://grafana.stelmashchuk.dev`, `TZ=UTC`.
- Data persisted at `/var/lib/grafana` (PVC). Reads metrics from Mongo `vps_metrics`.

---

## 7. Telegraf

- Image `telegraf:1.37.3`. Runs as a DaemonSet (was Swarm `mode: global`).
- Config (`telegraf.conf`): agent interval 10s; output **mongodb** → database `vps_metrics`,
  granularity seconds, DSN = authenticated Mongo URI (`$MONGO_URL`).
- Inputs to KEEP: `cpu` (totalcpu, report_active), `mem`, `disk` (ignores tmpfs/overlay/etc),
  `net`. Needs host `/proc`, `/sys`, `/etc` mounted (`HOST_PROC`/`HOST_SYS`/`HOST_ETC`).
- Input to DROP: `inputs.docker` (Docker socket) — k3s uses containerd, no socket.
  Per-container metrics are lost; revisit with metrics-server/cAdvisor only if needed.

---

## 8. Provisioning (was Ansible `install-docker.yml`)

Old flow installed Docker CE + `docker swarm init` on Ubuntu 24.04 via Ansible, triggered
by the `Setup VPS` workflow (`ROOT_SSH_PRIVATE_KEY`/`ROOT_SSH_PUBLIC_KEY`).

Replaced by `bootstrap/` (docs + scripts): k3s install, kubeconfig export →
`KUBE_CONFIG` secret, and Hetzner firewall. Captured in `bootstrap/README.md`.
