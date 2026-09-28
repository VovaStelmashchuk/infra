#!/usr/bin/env bash
set -euo pipefail

# Required environment variables:
: "${PGHOST:?need to set PGHOST}"
: "${PGPORT:?need to set PGPORT}"
: "${PGUSER:?need to set PGUSER}"
: "${PGPASSWORD:?need to set PGPASSWORD}"
: "${GCS_BUCKET:?need to set GCS_BUCKET}"
: "${GCS_FOLDER:?need to set GCS_FOLDER}"
: "${GCS_SA_KEY_BASE64:?need to set GCS_SA_KEY_BASE64}"

TS="$(date +'%Y-%m-%d_%H-%M')"
ARCHIVE="/tmp/pgdumpall-${TS}.sql.gz"

echo "[+] Dumping PostgreSQL → ${ARCHIVE}"
# pg_dumpall keeps roles and every database in one plain sql stream, the same
# "one file restores everything" property the mongo backup has.
# Connection settings come from the libpq PG* env vars: pg_dumpall runs pg_dump
# per database and drops the password from --dbname, but env vars are inherited.
pg_dumpall | gzip > "${ARCHIVE}"

# Authenticate to Google Cloud with the service account key (base64-encoded JSON).
export CLOUDSDK_CONFIG=/tmp/gcloud
# Archives are small and the service account cannot read bucket metadata,
# which parallel composite uploads need, so keep uploads single-stream.
export CLOUDSDK_STORAGE_PARALLEL_COMPOSITE_UPLOAD_ENABLED=False
KEY_FILE="$(mktemp)"
trap 'rm -f "${KEY_FILE}"' EXIT
echo "${GCS_SA_KEY_BASE64}" | base64 -d > "${KEY_FILE}"
gcloud auth activate-service-account --key-file="${KEY_FILE}"

UPLOAD_PATH="gs://${GCS_BUCKET}/${GCS_FOLDER}/pgdumpall-${TS}.sql.gz"
echo "[+] Uploading to GCS: ${UPLOAD_PATH}"

gcloud storage cp "${ARCHIVE}" "${UPLOAD_PATH}"

echo "[+] Done."
