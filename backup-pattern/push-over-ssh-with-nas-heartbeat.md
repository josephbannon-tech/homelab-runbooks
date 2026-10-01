# Push-over-SSH backup with a NAS-side heartbeat

The pattern behind every in-cluster backup job on the estate (Open WebUI, Radicale, Syncthing, Immich DB). The job pushes; the NAS verifies and only then writes the heartbeat; one shared alert covers every job.

## Shape

```text
CronJob (k3s)                                  NAS (TrueNAS)
  init "dump"  ──► emptyDir ──► "ship": tar | ssh ──► forced command: nas-backup-receive.sh <job>
  (optional: SQLite online-backup, pg_dump)        stream → tar -tzf gate → size floor → rename
                                                   → prune to N → write heartbeat LAST
```

- **Key per job**, restricted: `restrict,command="/path/nas-backup-receive.sh <job>" ssh-ed25519 ...`. The key can run one script and nothing else: no shell, no forwarding, no PTY. A compromised pod can write archives into one directory and touch one heartbeat file.
- **Host key pinned** in the job's secret (`known_hosts`), `StrictHostKeyChecking=yes`: a NAS rebuild that changes host keys fails loudly instead of trusting a new one.
- **Heartbeat written last**: `backup_last_success_timestamp_seconds{name="<job>-backup"}` into the NAS node_exporter textfile directory, atomic `mv`. Any failure before it leaves the previous timestamp, and `BackupHeartbeatStale` (36 h for daily jobs) fires. No per-job alert rule.
- **Integrity from listing, not size**: `tar -tzf` rejects a truncated stream. The size floor is only a guard against an empty tarball (~100 bytes); measure the first real archive before setting it (a mostly-empty SQLite file compressed to 36 KB where the design guessed 100 KB).
- **One dashboard tile per job** on the capacity/backup board, cadence-aware thresholds (yellow ~25 h, red ~50 h for daily).

## Adding a job (under an hour)

1. Generate a keypair on the operations host; seal the private key and the NAS `known_hosts` line into a `SealedSecret` in the app's namespace. Shred the plaintext.

   ```bash
   ssh-keygen -t ed25519 -N '' -C <job>-backup@<cluster> -f ./id_ed25519
   ssh-keyscan -t ed25519 <nas> > known_hosts
   kubectl create secret generic <job>-backup-ssh -n <ns> --from-file=id_ed25519 --from-file=known_hosts --dry-run=client -o yaml | kubeseal -o yaml > charts/secrets/<job>-backup-ssh.yaml
   shred -u id_ed25519
   ```

2. NAS: `mkdir backups/<job>`; append the restricted key line to root's authorized keys **through the middleware** (on TrueNAS the file is generated from the user record; a hand edit is lost):

   ```bash
   midclt call user.update <root-id> '{"sshpubkey": "<existing lines>\nrestrict,command=\"/mnt/.../bin/nas-backup-receive.sh <job>\" ssh-ed25519 AAAA... <job>-backup@<cluster>\n"}'
   ```

   Save the previous value first; a malformed update locks out every key. Verify with a fresh login before closing the session that made the change.
3. CronJob in the app's chart: one container (plain file tree) or init+main (a DB that needs a consistent dump). Mount the PVC read-only. The ship container runs as root in-container (the OpenSSH client fatals on a uid with no passwd entry and the key must be `0400`); drop all capabilities, add `DAC_READ_SEARCH` only if the app writes `0600` files. Schedule it before the off-site seed run so the seed ships last night's archive.
4. Add the archive to the off-site seed's latest-only group.
5. Dashboard tile; then the [first-unattended-night](../drills/first-unattended-night.md) check.
6. Restore runbook in the template shape, rehearsed once before real data lands.

## Failure modes seen

- Receiver floor too high → good archive rejected (2026-09-30). Measure first.
- `0600` identity files + caps-dropped root → torn archive, correctly rejected (2026-09-30). `DAC_READ_SEARCH`.
- `kubectl cp` into a caps-dropped container fails on chown; use `kubectl exec -i ... sh -c 'cat > file' < file`.
- A completed Job pod carries the app label; `kubectl wait --for=delete -l app=<x>` then waits on it forever. Select on the Deployment's pod-template hash or delete the Job first.
