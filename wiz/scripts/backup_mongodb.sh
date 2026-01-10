bash
#!/usr/bin/env bash
# MongoDB -> S3 backup script (designed to run on an EC2 instance with an instance profile
# that grants S3 PutObject permissions).
set -euo pipefail
IFS=$'\n\t'

# -------------------------
# Config (override via env)
# -------------------------
MONGO_HOST="${MONGO_HOST:-localhost}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_USER="${MONGO_USER:-}"        # leave empty to skip auth flags
MONGO_PASS="${MONGO_PASS:-}"
AUTH_DB="${AUTH_DB:-admin}"

BACKUP_PREFIX="${BACKUP_PREFIX:-mongodb_backup}"
TMPDIR="$(mktemp -d /tmp/mongo-backup.XXXXXX)"
BACKUP_NAME="${BACKUP_PREFIX}_$(date +%F_%H-%M-%S).gz"
LOCAL_ARCHIVE="${TMPDIR}/${BACKUP_NAME}"

# S3 target (required)
BUCKET="${BUCKET:-}"                # e.g. mongodbbackupsstorage002 or computed value from Terraform
S3_KEY_PREFIX="${S3_KEY_PREFIX:-}"  # optional prefix/folder inside the bucket, e.g. "backups/"
REGION="${AWS_REGION:-}"            # optional, aws cli picks up if not set

# AWS CLI options
AWS_RETRIES="${AWS_RETRIES:-3}"
AWS_RETRY_SLEEP="${AWS_RETRY_SLEEP:-5}"

# -------------------------
# Cleanup and trap
# -------------------------
cleanup() {
  rm -rf "${TMPDIR}" || true
}
trap cleanup EXIT

# -------------------------
# Preconditions
# -------------------------
command -v mongodump >/dev/null 2>&1 || { echo "ERROR: mongodump not found; install MongoDB Database Tools" >&2; exit 2; }
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found; install and configure it (EC2 instance role preferred)" >&2; exit 3; }

if [ -z "${BUCKET}" ]; then
  echo "ERROR: BUCKET is not set. Export BUCKET=<your-s3-bucket-name> or set it in the script." >&2
  exit 4
fi

# Create archive (prefer mongodump --archive --gzip when available)
echo "Creating MongoDB dump..."
if mongodump --help 2>&1 | grep -q -- --archive; then
  if [ -n "${MONGO_USER}" ] && [ -n "${MONGO_PASS}" ]; then
    mongodump --host "${MONGO_HOST}" --port "${MONGO_PORT}" \
      --username "${MONGO_USER}" --password "${MONGO_PASS}" --authenticationDatabase "${AUTH_DB}" \
      --archive="${LOCAL_ARCHIVE}" --gzip
  else
    mongodump --host "${MONGO_HOST}" --port "${MONGO_PORT}" \
      --archive="${LOCAL_ARCHIVE}" --gzip
  fi
else
  DUMP_DIR="${TMPDIR}/dump"
  mkdir -p "${DUMP_DIR}"
  if [ -n "${MONGO_USER}" ] && [ -n "${MONGO_PASS}" ]; then
    mongodump --host "${MONGO_HOST}" --port "${MONGO_PORT}" \
      --username "${MONGO_USER}" --password "${MONGO_PASS}" --authenticationDatabase "${AUTH_DB}" \
      --out "${DUMP_DIR}"
  else
    mongodump --host "${MONGO_HOST}" --port "${MONGO_PORT}" --out "${DUMP_DIR}"
  fi
  tar -C "${DUMP_DIR}" -czf "${LOCAL_ARCHIVE}" .
fi

echo "Archive created: ${LOCAL_ARCHIVE} (size: $(du -h "${LOCAL_ARCHIVE}" | cut -f1))"

# -------------------------
# Upload to S3 (with retries)
# -------------------------
S3_KEY="${S3_KEY_PREFIX}${BACKUP_NAME}"
S3_URI="s3://${BUCKET}/${S3_KEY}"

upload() {
  if [ -n "${REGION}" ]; then
    aws s3 cp "${LOCAL_ARCHIVE}" "${S3_URI}" --region "${REGION}" --only-show-errors --sse AES256
  else
    aws s3 cp "${LOCAL_ARCHIVE}" "${S3_URI}" --only-show-errors --sse AES256
  fi
}

echo "Uploading to ${S3_URI} ..."
n=0
until [ "${n}" -ge "${AWS_RETRIES}" ]
do
  if upload; then
    echo "Upload succeeded."
    break
  fi
  n=$((n+1))
  echo "Upload failed; retry ${n}/${AWS_RETRIES} in ${AWS_RETRY_SLEEP}s..."
  sleep "${AWS_RETRY_SLEEP}"
done

if [ "${n}" -ge "${AWS_RETRIES}" ]; then
  echo "ERROR: upload failed after ${AWS_RETRIES} attempts." >&2
  exit 5
fi

# Optionally print a presigned URL for quick download (valid for 1 hour)
if command -v aws >/dev/null 2>&1; then
  PRESIGNED_URL="$(aws s3 presign "${S3_URI}" --expires-in 3600 2>/dev/null || true)"
  if [ -n "${PRESIGNED_URL}" ]; then
    echo "Presigned URL (valid 1 hour): ${PRESIGNED_URL}"
  fi
fi

echo "MongoDB backup uploaded to: ${S3_URI}"
exit 0