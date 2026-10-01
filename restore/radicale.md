# Restore Radicale

**What is protected**: `/data/collections` (every calendar, task list and contact as `.ics`/`.vcf`, plus Radicale's per-collection cache). **Not**: nothing else exists; the htpasswd lives in a SealedSecret in Git.
**Source**: NAS `backups/radicale/radicale-<stamp>.tar.gz`, 14 generations, nightly 02:35; heartbeat `name="radicale-backup"`; in the off-site seed. **Last rehearsed**: 2026-09-30, passed (collections and a test event back), ~1 min.

## Before you start
- Phones keep syncing locally (DAVx5 / Tasks.org retry); a minute of 503s is invisible to them.
- Operator-owned replicas are declared on the `Application`.

## Steps
1. `scp nas:/mnt/.../backups/radicale/radicale-<stamp>.tar.gz /tmp/ && tar -tzf /tmp/radicale-<stamp>.tar.gz | head`.
2. `kubectl -n pim scale deploy radicale --replicas=0`; wait for the pod to go (select by the deployment, not `app=radicale`, which also matches completed backup Job pods).
3. Helper pod with PVC `radicale-data` at `/data`, running as root with `CHOWN`, `FOWNER`, `DAC_OVERRIDE` added. Copy the archive in via `exec -i ... cat >`.
4. In the helper:
   ```bash
   cd /data && tar -tzf /tmp/a.tar.gz >/dev/null && mv collections collections.pre-restore && tar -xzf /tmp/a.tar.gz -C /data && chown -R 2999:2999 /data/collections
   ```
   Radicale runs as uid 2999; the archive was written by root, so the `chown` is load-bearing.
5. Delete the helper; scale to 1; wait for Ready.

## Verify
```bash
curl -s -u <user>:<pw> -X PROPFIND -H 'Depth: 1' http://<node>:30232/<user>/   # 207 with the collections
curl -s -u <user>:<pw> http://<node>:30232/<user>/<calendar>/<some>.ics | grep SUMMARY
```
Remove `collections.pre-restore` once satisfied.

## Rollback
- Scale down, swap `collections.pre-restore` back, `chown`, scale up.

## Failure modes seen
- 2026-09-30: `kubectl wait --for=delete -l app=radicale` waited 60 s on the completed backup Job's pod. Delete the Job first or select on the ReplicaSet.
