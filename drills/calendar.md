# Drill calendar

Backups are rehearsed on a rotation, not when there is time. Each drill is logged with date, what was restored, from which archive, how long, and what was learned.

| Drill | Cadence | Next due | Last |
|---|---|---|---|
| Proxmox guest restore (rotate LXC / VM) | quarterly | 2026-12-08 | 2026-09-08, LXC, 31 s, PASSED |
| Off-site seed restore from a non-runner host | quarterly, with the USB refresh | 2026-12 | 2026-08-30, PASSED |
| Sealing-key recovery-unseal of every committed secret | after every monthly key renewal | first morning after the renewal | 2026-09-09, 7/7 |
| One stateful-service restore (rotate: Open WebUI, Radicale, Syncthing, Immich DB) | quarterly | 2026-12 | 2026-09-30 / 10-01, all four except Syncthing |
| Documentation accuracy audit | quarterly | 2026-12-08 | 2026-09-08 |

## Log format

```text
- YYYY-MM-DD: <drill>, <archive or snapshot>, <seconds>, PASSED|FAILED. Learned: <one line>. Follow-up: <TODO link or none>.
```
