#!/usr/bin/env bash
set -euo pipefail

# Required environment variables:
: "${POSTGRES_URI:?need to set POSTGRES_URI}"
: "${GCS_BUCKET:?need to set GCS_BUCKET}"
: "${GCS_FOLDER:?need to set GCS_FOLDER}"
: "${GCS_SA_KEY_BASE64:?need to set GCS_SA_KEY_BASE64}"

TS="$(date +'%Y-%m-%d_%H-%M')"
ARCHIVE="/tmp/pgdumpall-${TS}.sql.gz"

echo "[+] Dumping PostgreSQL → ${ARCHIVE}"
# pg_dumpall keeps roles and every database in one plain sql stream, the same
# "one file restores everything" property the mongo backup has.
pg_dumpall --dbname="${POSTGRES_URI}" | gzip > "${ARCHIVE}"

# Authenticate to Google Cloud with the service account key (base64-encoded JSON).
export CLOUDSDK_CONFIG=/tmp/gcloud
KEY_FILE="$(mktemp)"
trap 'rm -f "${KEY_FILE}"' EXIT
echo "${GCS_SA_KEY_BASE64}" | base64 -d > "${KEY_FILE}"
gcloud auth activate-service-account --key-file="${KEY_FILE}"

UPLOAD_PATH="gs://${GCS_BUCKET}/${GCS_FOLDER}/pgdumpall-${TS}.sql.gz"
echo "[+] Uploading to GCS: ${UPLOAD_PATH}"

gcloud storage cp "${ARCHIVE}" "${UPLOAD_PATH}"

echo "[+] Done."
