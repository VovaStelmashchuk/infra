# Bootstrap — one-time cluster setup

This replaces the old Ansible `install-docker.yml` playbook + `Setup VPS` workflow.
It is the manual, one-time setup of a fresh Hetzner/Proxmox VM into a working k3s node
that the GitHub Actions deploy workflow can target. Everything after this is `kubectl apply`.

Run these steps once, on a fresh VM, as root. Goal: a single-node k3s cluster reachable
on `<public-ip>:6443`, with cert-manager installed and the GitHub secrets populated.

---

## 1. Install k3s

k3s ships with Traefik (ingress), local-path (default StorageClass), CoreDNS, and
metrics-server — no extra components needed.

```sh
# --tls-san makes the API certificate valid for the public IP we connect over.
curl -sfL https://get.k3s.io | sh -s - server \
  --tls-san <public-ip>

# verify
k3s kubectl get nodes
k3s kubectl get pods -A
```

The admin kubeconfig is written to `/etc/rancher/k3s/k3s.yaml`.

## 2. Export the kubeconfig for GitHub Actions

The deploy workflow authenticates with a base64-encoded admin kubeconfig stored as the
`KUBE_CONFIG` repo secret, with its server line pointed at the public IP (the on-disk
file points at `127.0.0.1`).

```sh
sed 's#https://127.0.0.1:6443#https://<public-ip>:6443#' /etc/rancher/k3s/k3s.yaml \
  | base64 -w0
```

Copy the output into the `KUBE_CONFIG` GitHub Actions secret (see repo README).

> SECURITY TODO: this is the cluster-admin kubeconfig. Replace it with a scoped
> ServiceAccount + RBAC limited to the `infra` namespace as a hardening step.

## 3. Install cert-manager

Needed for Let's Encrypt TLS via the `ClusterIssuer` in
`bootstrap/cert-manager/cluster-issuer.yaml` (which the deploy workflow applies).
Install the controller + CRDs once:

```sh
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
kubectl wait --for=condition=Available --timeout=120s \
  -n cert-manager deployment/cert-manager-webhook
```

(Pin to whatever cert-manager release you want; bump it deliberately.)

## 4. Hetzner firewall

Lock the box down to only what the cluster needs. Configure this in the Hetzner Cloud
firewall (or `ufw` on the host if dedicated). Minimum inbound:

| Port | Proto | Purpose | Source |
|---|---|---|---|
| 22 | TCP | SSH | your IP(s) only |
| 80 | TCP | HTTP (Traefik, ACME HTTP-01) | any |
| 443 | TCP | HTTPS (Traefik) | any |
| 6443 | TCP | k3s API (kubectl from GitHub Actions) | any (ideally GitHub runner ranges / your IP) |

Everything else inbound: deny.

> SECURITY TODO: 6443 open to any is convenient but broad. Narrow it to GitHub Actions
> runner IP ranges or run deploys through a self-hosted runner / tailnet.

## 5. Create the application secrets

See the repo [README](../README.md#secrets) — the `mongo-secret` and `s3-secret` must
exist in the `infra` namespace before the first deploy (the namespace itself is created
by the deploy workflow, so create it first if you're seeding secrets by hand:
`kubectl create namespace infra`).

## 6. First deploy

Push to `main` (or re-run the workflow). The deploy workflow builds the custom images,
creates the namespace, and applies all manifests. Mongo comes up, the `mongo-rs-init`
Job initiates the replica set, and cert-manager issues certs for the ingress hosts.
