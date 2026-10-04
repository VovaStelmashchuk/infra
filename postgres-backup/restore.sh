#!/usr/bin/env bash
set -euo pipefail

# Restores the newest (or a chosen) backup made by backup.sh, run by the
# "Restore from backup" workflow, see scripts/restore-on-host.sh.

# Required environment variables:
: "${POSTGRES_URI:?need to set POSTGRES_URI}"
: "${GCS_BUCKET:?need to set GCS_BUCKET}"
: "${GCS_FOLDER:?need to set GCS_FOLDER}"
: "${GCS_SA_KEY_BASE64:?need to set GCS_SA_KEY_BASE64}"
BACKUP_PREFIX="pgdumpall-"

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

# pg_dumpall output is not "clean": it creates every database and the objects
# of the postgres database, so wipe those first to get the same state as the
# backup instead of a mix of both.
echo "[+] Dropping existing databases"
psql --dbname="${POSTGRES_URI}" -At -c \
  "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres', 'template0', 'template1')" |
  while read -r db; do
    echo "    - ${db}"
    psql --dbname="${POSTGRES_URI}" -v ON_ERROR_STOP=1 -c "DROP DATABASE \"${db}\" WITH (FORCE)"
  done
psql --dbname="${POSTGRES_URI}" -v ON_ERROR_STOP=1 \
  -c 'DROP SCHEMA IF EXISTS public CASCADE' \
  -c 'CREATE SCHEMA public'

# Not ON_ERROR_STOP: the dump always tries to create the roles that already
# exist (at least the superuser), those "already exists" errors are expected.
echo "[+] Restoring PostgreSQL"
gunzip -c "${ARCHIVE}" | psql --dbname="${POSTGRES_URI}" --quiet

echo "[+] Done."
