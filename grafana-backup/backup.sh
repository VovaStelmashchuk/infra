#!/usr/bin/env bash
set -euo pipefail

: "${GRAFANA_DATA_DIR:?need to set GRAFANA_DATA_DIR}"
: "${GCS_BUCKET:?need to set GCS_BUCKET}"
: "${GCS_FOLDER:?need to set GCS_FOLDER}"
: "${GCS_SA_KEY_BASE64:?need to set GCS_SA_KEY_BASE64}"

TS="$(date +'%Y-%m-%d_%H-%M')"
ARCHIVE="/tmp/grafana-backup-${TS}.tar.gz"

if [ ! -e "${GRAFANA_DATA_DIR}" ]; then
    echo "Error: Path ${GRAFANA_DATA_DIR} does not exist."
    exit 1
fi

echo "Archiving Grafana data from ${GRAFANA_DATA_DIR} → ${ARCHIVE}"

tar -czf "${ARCHIVE}" -C "$(dirname "${GRAFANA_DATA_DIR}")" "$(basename "${GRAFANA_DATA_DIR}")"

# Authenticate to Google Cloud with the service account key (base64-encoded JSON).
export CLOUDSDK_CONFIG=/tmp/gcloud
KEY_FILE="$(mktemp)"
trap 'rm -f "${KEY_FILE}"' EXIT
echo "${GCS_SA_KEY_BASE64}" | base64 -d > "${KEY_FILE}"
gcloud auth activate-service-account --key-file="${KEY_FILE}"

UPLOAD_PATH="gs://${GCS_BUCKET}/${GCS_FOLDER}/grafana-backup-${TS}.tar.gz"
echo "Uploading to GCS: ${UPLOAD_PATH}"

gcloud storage cp "${ARCHIVE}" "${UPLOAD_PATH}"

echo "Done."

exit 0
