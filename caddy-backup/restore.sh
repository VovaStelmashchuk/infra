#!/usr/bin/env bash
set -euo pipefail

# Restores the newest (or a chosen) backup made by backup.sh, run by the
# "Restore from backup" workflow, see scripts/restore-on-host.sh.

# Required environment variables:
: "${CADDY_DATA_DIR:?need to set CADDY_DATA_DIR}"
: "${GCS_BUCKET:?need to set GCS_BUCKET}"
: "${GCS_FOLDER:?need to set GCS_FOLDER}"
: "${GCS_SA_KEY_BASE64:?need to set GCS_SA_KEY_BASE64}"
BACKUP_PREFIX="caddy-backup-"

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

# The archive holds the data dir itself (see backup.sh), so extract it next to
# it after emptying the current content.
echo "[+] Restoring Caddy data into ${CADDY_DATA_DIR}"
find "${CADDY_DATA_DIR}" -mindepth 1 -delete
tar -xzf "${ARCHIVE}" -C "$(dirname "${CADDY_DATA_DIR}")"
ls -la "${CADDY_DATA_DIR}"

echo "[+] Done."
