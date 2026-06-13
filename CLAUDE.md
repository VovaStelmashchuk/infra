# CLAUDE.md

Guidance for working in this repo.

## What this repo is

Shared **cluster infrastructure** for a single-node **k3s** cluster, as raw Kubernetes
manifests. Everything lives in the `infra` namespace. This repo does **not** contain
application code or application ingress — apps (cv, nest2d, mixdrinks, ypod, velonuxt)
live in their own repos and carry their own manifests.

## Guiding philosophy

No over-engineering. The smallest thing that works, with all the necessary pieces.
Document one-time manual steps clearly. Prefer boring, explicit YAML over abstractions.

## Conventions

- **Raw YAML in folders**, applied with `kubectl apply`. Do **not** introduce Kustomize or
  Helm unless real repetition appears and is discussed first.
- One concern per file (`service.yaml`, `deployment.yaml`, `ingress.yaml`, …).
- All resources set `namespace: infra`.
- **Ingress**: Traefik (built into k3s), `ingressClassName: traefik`, TLS via cert-manager
  (`cert-manager.io/cluster-issuer: letsencrypt`). One Secret per host (`<name>-tls`).
- **Storage**: built-in `local-path` StorageClass (default) — omit `storageClassName`.
- **Custom images** we build go to `ghcr.io/vovastelmashchuk/<name>`. Reference them as
  `:latest` in manifests; the deploy workflow pins them to the commit SHA at apply time.
  Stock upstream images (mongo, telegraf, compass-web, nginx) are pinned to explicit
  version tags directly in the manifest.
- **Secrets** are generated dynamically by GitHub Actions during the deploy CI workflow and
  **never committed**. Manifests reference them via `secretKeyRef` / Secret volumes.
  The combined secret is named `secret` (keys: `username`, `password`, `uri`, `keyfile`,
  `endpoint`, `bucket`, `access-key-id`, `secret-access-key`).
- **Schedules** (CronJobs) are UTC.

## Image versions (bump deliberately; Dependabot watches the Dockerfiles)

- mongo `8.2.3` (StatefulSet + init Job), mongo backup base `8.2.5`
- grafana `12.4.0-...-ubuntu` + `haohanyang-mongodb-datasource` v0.4.1 (unsigned)
- telegraf `1.37.3`
- compass-web `0.3.1`

## When changing things

- Validate before considering done:
  `kubectl apply --dry-run=client -R -f <dir>` (or `-o yaml | kubeconform` if available).
- The `mongo-rs-init` Job's pod template is immutable — to change it, delete the Job first.
- Telegraf's ConfigMap is generated in CI from `monitoring/telegraf/telegraf.conf`; edit
  the `.conf`, not a checked-in ConfigMap.
- No `inputs.docker` in Telegraf — k3s uses containerd, there is no Docker socket.
- If you add a new manifest directory, add it to the `kubectl apply` list in
  `.github/workflows/deploy.yml`.

## Deploy flow

Push to `main` → GitHub Actions builds custom images to GHCR → `kubectl apply` via the
base64 `KUBE_CONFIG` secret. One-time cluster setup is in `bootstrap/README.md`.

## Security TODOs (deferred on purpose)

Hetzner firewall hardening (`:6443`), scoped ServiceAccount + RBAC instead of admin
kubeconfig, and sealed-secrets. See README.
