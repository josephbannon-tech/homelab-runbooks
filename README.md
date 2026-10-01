# homelab-runbooks

Backup and disaster-recovery runbooks from a single-node homelab run as production-shape infrastructure. One task per file, written to be executed under mild stress: numbered steps, copy-pasteable commands, the expected output stated, and the failure modes named. Every restore here has been rehearsed at least once; the date is in the file.

Alert-triage runbooks live next to the alerts that reference them, in [homelab-observability](https://github.com/josephbannon-tech/homelab-observability/tree/main/runbooks). The deployable configuration (charts, CronJobs, alert rules) is in [homelab-gitops](https://github.com/josephbannon-tech/homelab-gitops). This repo holds the discipline: how a data store gets a backup on day one, how it gets restored, and how the estate proves both keep working.

## The rule

A backup is not real until a restore has been rehearsed. Every stateful service ships with three things on the day it goes live: a backup job that produces a latest-state archive on the NAS with a heartbeat metric, inclusion of that archive in the off-site seed, and a restore runbook in this shape. The heartbeat is written by the receiving side only after the archive verifies, so a failure anywhere in the chain goes stale and pages through one shared alert instead of a rule per job.

## Backup pattern

- [push-over-ssh-with-nas-heartbeat.md](backup-pattern/push-over-ssh-with-nas-heartbeat.md): the pattern every in-cluster backup job uses, and how to add a new one in under an hour.
- [stateful-apps-on-argocd.md](backup-pattern/stateful-apps-on-argocd.md): why `kubectl scale --replicas=0` gets undone by GitOps self-heal, and the two ways to make a restore window stick.
- [scripts/nas-backup-receive.sh](scripts/nas-backup-receive.sh): the NAS-side forced-command receiver.

## Restore runbooks

| Data store | Runbook | Last rehearsed | Restore time |
|---|---|---|---|
| Open WebUI (SQLite, uploads, vector store) | [restore/open-webui.md](restore/open-webui.md) | 2026-09-30 | ~1 min downtime |
| Radicale (CalDAV / task lists) | [restore/radicale.md](restore/radicale.md) | 2026-09-30 | ~1 min |
| Syncthing (device identity + vault) | [restore/syncthing.md](restore/syncthing.md) | not yet (vault empty) | est. 2 min |
| Immich database (CloudNativePG Postgres) | [restore/immich-database.md](restore/immich-database.md) | 2026-10-01 | 14 s for the restore itself |
| Sealed Secrets sealing keys | [restore/sealed-secrets-keys.md](restore/sealed-secrets-keys.md) | 2026-09-09 (7 of 7 decrypt) | seconds; must precede the app-of-apps |
| Proxmox guest from a vzdump archive | [restore/proxmox-guest-from-vzdump.md](restore/proxmox-guest-from-vzdump.md) | 2026-09-08 (LXC, 31 s) | 1 to 5 min |
| Off-site seed (restic to cloud storage) | [restore/offsite-seed.md](restore/offsite-seed.md) | 2026-08-30 | 13 s for 666 MiB |

## Drills

- [drills/calendar.md](drills/calendar.md): the quarterly rotation and the log format.
- [drills/first-unattended-night.md](drills/first-unattended-night.md): the morning-after check for any new backup job.

## Runbook template

```markdown
# Restore <service>

**What is protected**: <paths / tables>. **What is not**: <derivable data left out, and why>.
**Source**: <where the archive lands, retention, heartbeat name>. **Last rehearsed**: <date, result, time taken>.

## Before you start
- <preconditions, what will be down, who to tell>

## Steps
1. ...
   Expected: ...

## Verify
- <the check that proves the data is back, not just the pod>

## Rollback
- ...

## Failure modes seen
- Symptom → cause → fix (one line each, dated)
```

## Lessons learned

- **Symptom:** a restore rehearsal's scale-down was undone within 30 seconds, twice. **Root cause:** GitOps self-heal, on two layers (the app, and the app-of-apps that owns the app's spec). **Fix:** operator-owned replicas via `ignoreDifferences` on stateful apps; details in [stateful-apps-on-argocd.md](backup-pattern/stateful-apps-on-argocd.md).
- **Symptom:** a backup job reported success for weeks while the archive could not decrypt three of seven secrets. **Root cause:** the sealing-key export had been taken once, with one key, while the controller rotated monthly. **Fix:** the export re-runs nightly and a recovery-unseal test is part of the drill; see [restore/sealed-secrets-keys.md](restore/sealed-secrets-keys.md).
- **Symptom:** a first backup run produced an archive that the receiver rejected. **Root cause:** the service writes its identity files `0600`, and the shipping container ran with every capability dropped. **Fix:** `DAC_READ_SEARCH` only. The rejection was the receiver's integrity gate working.
- **Symptom:** a size floor copied from a design doc rejected a real, good archive. **Root cause:** a mostly-empty SQLite file compresses to a fraction of the planned figure. **Fix:** measure the first real archive before choosing a floor; integrity comes from listing the tarball, not from its size.
