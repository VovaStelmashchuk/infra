#!/usr/bin/env bash
set -euo pipefail

# Runs on the VPS (piped over ssh by the "Restore from backup" workflow).
#
# Usage: restore-on-host.sh <backup service> <backup file|latest> [service to stop]
#
# The restore runs as a one-off container from the image of the deployed backup
# service, with that service's env, network and volumes. So the restore uses the
# same credentials, bucket folder and data volume as the backup, and no secret
# has to be sent from GitHub. The optional service is scaled to 0 during the
# restore (for apps holding their data files open) and scaled back afterwards.

STACK="${STACK:-infra}"
BACKUP_SERVICE="${STACK}_${1:?need the backup service name}"
BACKUP_FILE="${2:-latest}"
STOP_SERVICE="${3:+${STACK}_${3}}"

if ! docker service inspect "${BACKUP_SERVICE}" > /dev/null 2>&1; then
  echo "[!] Service ${BACKUP_SERVICE} not found, deploy the stack first."
  exit 1
fi

spec() { docker service inspect "${BACKUP_SERVICE}" --format "$1"; }

IMAGE="$(spec '{{.Spec.TaskTemplate.ContainerSpec.Image}}')"
ENV_FILE="$(umask 077 && mktemp)"
trap 'rm -f "${ENV_FILE}"' EXIT
spec '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' > "${ENV_FILE}"
echo "BACKUP_FILE=${BACKUP_FILE}" >> "${ENV_FILE}"

RUN_ARGS=()
# Only attachable networks can be joined by a plain container. The stack's
# implicit default network is not attachable, services that use only it
# (caddy, grafana backups) need no internal network, just internet access,
# which the default bridge gives.
for network in $(spec '{{range .Spec.TaskTemplate.Networks}}{{.Target}} {{end}}'); do
  if [ "$(docker network inspect "${network}" --format '{{.Attachable}}')" = "true" ]; then
    RUN_ARGS+=(--network "${network}")
  else
    echo "[i] Skipping network ${network}, it is not attachable"
  fi
done
while read -r mount; do
  [ -n "${mount}" ] && RUN_ARGS+=(-v "${mount}")
done < <(spec '{{range .Spec.TaskTemplate.ContainerSpec.Mounts}}{{.Source}}:{{.Target}}{{println}}{{end}}')

if [ -n "${STOP_SERVICE}" ]; then
  REPLICAS="$(docker service inspect "${STOP_SERVICE}" --format '{{.Spec.Mode.Replicated.Replicas}}')"
  echo "[+] Stopping ${STOP_SERVICE} (replicas ${REPLICAS} -> 0)"
  docker service scale --detach=false "${STOP_SERVICE}=0"
  trap 'rm -f "${ENV_FILE}"; echo "[+] Starting ${STOP_SERVICE} again"; docker service scale --detach=false "${STOP_SERVICE}=${REPLICAS}"' EXIT
fi

echo "[+] Restoring with ${IMAGE}"
docker run --rm \
  --env-file "${ENV_FILE}" \
  "${RUN_ARGS[@]}" \
  --entrypoint /usr/local/bin/restore.sh \
  "${IMAGE}"
