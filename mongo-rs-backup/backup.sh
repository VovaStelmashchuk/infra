#!/usr/bin/env bash
set -euo pipefail

# Required environment variables:
: "${MONGO_URI:?need to set MONGO_URI}"
: "${GCS_BUCKET:?need to set GCS_BUCKET}"
: "${GCS_FOLDER:?need to set GCS_FOLDER}"
: "${GCS_SA_KEY_BASE64:?need to set GCS_SA_KEY_BASE64}"

TS="$(date +'%Y-%m-%d_%H-%M')"
ARCHIVE="/tmp/mongodump-${TS}.gz"

echo "[+] Dumping MongoDB → ${ARCHIVE}"
mongodump \
  --uri="${MONGO_URI}" \
  --archive="${ARCHIVE}" \
  --gzip

# Authenticate to Google Cloud with the service account key (base64-encoded JSON).
export CLOUDSDK_CONFIG=/tmp/gcloud
KEY_FILE="$(mktemp)"
trap 'rm -f "${KEY_FILE}"' EXIT
echo "${GCS_SA_KEY_BASE64}" | base64 -d > "${KEY_FILE}"
gcloud auth activate-service-account --key-file="${KEY_FILE}"

UPLOAD_PATH="gs://${GCS_BUCKET}/${GCS_FOLDER}/mongodump-${TS}.gz"
echo "[+] Uploading to GCS: ${UPLOAD_PATH}"

gcloud storage cp "${ARCHIVE}" "${UPLOAD_PATH}"

echo "[+] Done." 
