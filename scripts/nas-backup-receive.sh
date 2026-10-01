#!/bin/bash
# nas-backup-receive.sh — generic NAS-side receiver for push-over-SSH backup jobs.
#
# Invoked ONLY as an SSH forced command, one restricted key per job:
#   restrict,command="/mnt/JBNAS_SSD/data/bin/nas-backup-receive.sh <job>" ssh-ed25519 ...
# The client streams a .tar.gz on stdin and passes the archive stamp
# (YYYYmmdd-HHMM) as the SSH command; both are validated before use.
# Writes into exactly one directory (backups/<job>/) and one heartbeat file.
#
# Order matters: stream -> tar integrity gate -> size floor -> rename into
# place -> prune -> heartbeat LAST, so any earlier failure leaves the previous
# timestamp in place and BackupHeartbeatStale fires.
#
# First job on it: radicale (2026-09-30). open-webui keeps its own
# open-webui-backup-receive.sh (identical logic, job name hard-coded) until a
# quiet moment moves its key line over. Canonical copy: homelab/scripts/.
# Deploy: scp to root@192.168.0.201:/mnt/JBNAS_SSD/data/bin/ ; chmod 755.
set -euo pipefail

JOB="${1:-}"
if ! [[ "$JOB" =~ ^[a-z0-9-]{2,32}$ ]]; then
  echo "receive: bad or missing job name '${JOB}'" >&2
  exit 64
fi
DEST="/mnt/JBNAS_SSD/data/backups/${JOB}"
NAS_TEXTFILE="/mnt/JBNAS_SSD/data/node_exporter/textfile_collector"
RETAIN="${RETAIN:-14}"
# Floor for "suspiciously small" (an empty tarball is ~100 bytes). Torn
# streams are caught by tar -tzf, not here.
MIN_BYTES="${MIN_BYTES:-1000}"

STAMP="${SSH_ORIGINAL_COMMAND:-}"
if ! [[ "$STAMP" =~ ^[0-9]{8}-[0-9]{4}$ ]]; then
  echo "receive[${JOB}]: bad or missing stamp '${STAMP}'" >&2
  exit 64
fi

OUT="${DEST}/${JOB}-${STAMP}.tar.gz"
PART="${OUT}.part"
# Remove the partial on ANY failure (ERR alone misses an explicit `exit N`).
trap '[ $? -eq 0 ] || rm -f "$PART"' EXIT

mkdir -p "$DEST"
cat > "$PART"

tar -tzf "$PART" > /dev/null
[ "$(stat -c%s "$PART")" -ge "$MIN_BYTES" ] || { echo "receive[${JOB}]: archive too small" >&2; exit 65; }
mv "$PART" "$OUT"

ls -t "${DEST}/${JOB}"-*.tar.gz | tail -n +$((RETAIN+1)) | xargs -r rm -f

HB="${JOB}-backup"
echo "backup_last_success_timestamp_seconds{name=\"${HB}\"} $(date +%s)" > "${NAS_TEXTFILE}/${HB}.prom.tmp"
mv "${NAS_TEXTFILE}/${HB}.prom.tmp" "${NAS_TEXTFILE}/${HB}.prom"
echo "receive[${JOB}]: stored $(basename "$OUT") ($(stat -c%s "$OUT") bytes)"
