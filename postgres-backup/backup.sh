#!/usr/bin/env bash
set -euo pipefail

# Required environment variables:
: "${POSTGRES_URI:?need to set POSTGRES_URI}"
: "${S3_BUCKET:?need to set S3_BUCKET}"
: "${S3_ACCESS_KEY_ID:?need to set S3_ACCESS_KEY_ID}"
: "${S3_SECRET_ACCESS_KEY:?need to set S3_SECRET_ACCESS_KEY}"
: "${S3_FOLDER:?need to set S3_FOLDER}"
: "${S3_ENDPOINT:?need to set S3_ENDPOINT}"

TS="$(date +'%Y-%m-%d_%H-%M')"
ARCHIVE="/tmp/pgdumpall-${TS}.sql.gz"

echo "[+] Dumping PostgreSQL → ${ARCHIVE}"
# pg_dumpall keeps roles and every database in one plain sql stream, the same
# "one file restores everything" property the mongo backup has.
pg_dumpall --dbname="${POSTGRES_URI}" | gzip > "${ARCHIVE}"

UPLOAD_PATH="s3://${S3_BUCKET}/${S3_FOLDER}/pgdumpall-${TS}.sql.gz"
echo "[+] Uploading to S3: ${UPLOAD_PATH}"

export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"

aws --endpoint-url="$S3_ENDPOINT" s3 cp "$ARCHIVE" "$UPLOAD_PATH"

echo "[+] Done."
