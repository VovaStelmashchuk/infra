#!/usr/bin/env bash
set -euo pipefail

# Restores the newest (or a chosen) backup made by backup.sh, run by the
# "Restore from backup" workflow, see scripts/restore-on-host.sh.

# Required environment variables:
: "${MONGO_URI:?need to set MONGO_URI}"
: "${GCS_BUCKET:?need to set GCS_BUCKET}"
: "${GCS_FOLDER:?need to set GCS_FOLDER}"
: "${GCS_SA_KEY_BASE64:?need to set GCS_SA_KEY_BASE64}"
BACKUP_PREFIX="mongodump-"

# BACKUP_FILE is a file name inside GCS_FOLDER, a full gs:// url, or "latest".
BACKUP_FILE="${BACKUP_FILE:-latest}"

# Authenticate to Google Cloud with the service account key (base64-encoded JSON).
# Restore needs to list and read objects, so the account needs
# `Storage Object Viewer` on the bucket in addition to `Storage Object Creator`.
export CLOUDSDK_CONFIG=/tmp/gcloud
KEY_FILE="$(mktemp)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${KEY_FILE}" "${WORK_DIR}"' EXIT
echo "${GCS_SA_KEY_BASE64}" | base64 -d > "${KEY_FILE}"
gcloud auth activate-service-account --key-file="${KEY_FILE}"

if [ "${BACKUP_FILE}" = "latest" ]; then
  # File names carry a sortable timestamp, so the last one is the newest.
  OBJECT="$(gcloud storage ls "gs://${GCS_BUCKET}/${GCS_FOLDER}/" | { grep "/${BACKUP_PREFIX}" || true; } | sort | tail -n 1)"
  if [ -z "${OBJECT}" ]; then
    echo "[!] No ${BACKUP_PREFIX}* backup found in gs://${GCS_BUCKET}/${GCS_FOLDER}/"
    exit 1
  fi
elif [[ "${BACKUP_FILE}" == gs://* ]]; then
  OBJECT="${BACKUP_FILE}"
else
  OBJECT="gs://${GCS_BUCKET}/${GCS_FOLDER}/${BACKUP_FILE}"
fi

ARCHIVE="${WORK_DIR}/$(basename "${OBJECT}")"
echo "[+] Downloading ${OBJECT}"
gcloud storage cp "${OBJECT}" "${ARCHIVE}"

wait_for_mongo() {
  echo "[+] Waiting for MongoDB"
  for _ in $(seq 1 60); do
    if mongosh "${MONGO_URI}" --quiet --eval 'db.runCommand({ ping: 1 })' > /dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  echo "[!] MongoDB is not reachable"
  return 1
}

# One collection and one insert worker at a time: big collections (gridfs
# chunks) restored in parallel push mongod out of memory on a small VPS, which
# shows up as "connection reset by peer". --drop makes a rerun replace what a
# failed attempt already wrote, so retrying is safe.
MAX_ATTEMPTS=3
for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
  wait_for_mongo
  echo "[+] Restoring MongoDB, attempt ${attempt}/${MAX_ATTEMPTS} (--drop replaces the collections in the backup)"
  if mongorestore \
    --uri="${MONGO_URI}" \
    --drop \
    --gzip \
    --numParallelCollections=1 \
    --numInsertionWorkersPerCollection=1 \
    --archive="${ARCHIVE}"; then
    echo "[+] Done."
    exit 0
  fi
  echo "[!] mongorestore failed"
  sleep 10
done

echo "[!] Restore failed after ${MAX_ATTEMPTS} attempts, check: docker service ps infra_mongo-rs-1 --no-trunc"
exit 1
