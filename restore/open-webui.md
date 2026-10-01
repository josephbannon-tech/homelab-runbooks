# Restore Open WebUI

**What is protected**: `webui.db` (users, chats, settings; copied with the SQLite online-backup API, consistent under WAL), `uploads/`, `vector_db/`. **Not**: `cache/` (the embedding model, re-downloaded on first start).
**Source**: NAS `backups/open-webui/open-webui-<YYYYmmdd-HHMM>.tar.gz`, 14 generations, nightly 02:30; heartbeat `name="open-webui-backup"`; latest archive in the off-site seed. **Last rehearsed**: 2026-09-30, passed, about a minute of downtime.

## Before you start

- Users lose the chat UI for about a minute. The LLM backends are untouched.
- The app's `Application` has operator-owned replicas; confirm: `kubectl -n argocd get application open-webui -o jsonpath='{.spec.ignoreDifferences}'`. If empty, use the fallback in [stateful-apps-on-argocd.md](../backup-pattern/stateful-apps-on-argocd.md).

## Steps

1. Fetch and check the archive on the operations host:

   ```bash
   scp nas:/mnt/.../backups/open-webui/open-webui-<stamp>.tar.gz /tmp/ && tar -tzf /tmp/open-webui-<stamp>.tar.gz
   ```

   Expected: `webui.db`, `uploads/`, `vector_db/...`.
2. Scale down and confirm it holds:

   ```bash
   kubectl -n open-webui scale sts open-webui --replicas=0
   kubectl -n open-webui wait --for=delete pod/open-webui-0 --timeout=120s; sleep 30; kubectl -n open-webui get pods
   ```

3. Helper pod: the app image (already on the node), `command: ["sleep","900"]`, `runAsUser: 0`, PVC `open-webui` at `/data` read-write. Copy the archive in with `kubectl exec -i owui-restore -- sh -c 'cat > /tmp/a.tar.gz' < /tmp/open-webui-<stamp>.tar.gz` (not `kubectl cp`).
4. In the helper:

   ```bash
   cd /data && mv webui.db webui.db.pre-restore && rm -f webui.db-wal webui.db-shm && tar -xzf /tmp/a.tar.gz --no-same-owner -C /data
   ```

   On a fresh PVC skip the `mv`.
5. Delete the helper; `kubectl -n open-webui scale sts open-webui --replicas=1`; wait for Ready; `curl -sf http://<node>:<nodeport>/health`.

## Verify

```bash
kubectl -n open-webui exec open-webui-0 -c open-webui -- python3 -c "import sqlite3; c=sqlite3.connect('file:/app/backend/data/webui.db?mode=ro', uri=True); print(c.execute('pragma integrity_check').fetchone(), c.execute('select count(*) from user').fetchone(), c.execute('select count(*) from chat').fetchone())"
```

Expected: `('ok',)` and the user/chat counts you expect. Remove `webui.db.pre-restore` once satisfied.

## Rollback

- Scale down, `mv webui.db.pre-restore webui.db` in the helper, scale up.

## Failure modes seen

- 2026-09-30: `kubectl cp` failed (`tar: Cannot change ownership`) into the caps-dropped helper → use `exec -i ... cat >`.
- 2026-09-30: self-heal re-scaled the StatefulSet mid-swap → operator-owned replicas rule (above).
