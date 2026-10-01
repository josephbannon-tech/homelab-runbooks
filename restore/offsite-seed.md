# Restore the off-site seed

**What is protected**: the "LLM-rebuildable seed": the knowledge base (every host's rebuild procedure), configs and credential backups, IaC state, and the latest archive of each stateful service and game save. Not media, telemetry or VM images. restic repository on cloud storage, client-side encrypted; the password lives in a password manager and on paper, never only inside the estate.
**Last rehearsed**: 2026-08-30 from a host that is not the backup runner (full `seed-core`, 666 MiB in 13 s; sha256 of a restored file matched the source).

## Before you start
- You need: restic, rclone, the rclone remote re-authorised, and the restic password. The rehearsal host did not have the first two installed; budget ten minutes.

## Steps
1. `export RESTIC_REPOSITORY="rclone:<remote>:<path>"; restic snapshots` (expect daily `seed-core` and `seed-worlds` snapshots).
2. `restic restore latest --tag seed-core --target /restore/seed`
3. `restic restore latest --tag seed-worlds --target /restore/worlds`
4. Open `/restore/seed/.../docs/` and follow the rebuild procedure for the host you need. Each stateful service's latest archive is under `/restore/worlds/...` for the matching restore runbook in this repo.

## Verify
- `sha256sum` of a restored file against a known value (the knowledge base's own index file is a good one).
- `restic check` on a Sunday if the weekly check has not run.

## DR test format
Hand the restored seed to a fresh assistant session and ask it to rebuild one host. Where it gets stuck is a documentation gap, which is the finding.

## Failure modes seen
- Retention shipped as keep-last 2 instead of 1 and the repository breached quota in week 1; the worlds group is latest-only by design.
- Pruning did not free cloud quota until the remote's trash behaviour was turned off.
