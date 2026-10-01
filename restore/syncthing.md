# Restore Syncthing

**What is protected**: `config/` (device identity: `cert.pem`, `key.pem`, `config.xml`; peers stay paired only if this comes back) and `vault/` (the replicated folder). **Not**: the index database (`index-v*`, rebuilt on start) and `.stversions` trash.
**Source**: NAS `backups/syncthing/syncthing-<stamp>.tar.gz`, 14 generations, nightly 02:40; heartbeat `name="syncthing-backup"`; in the off-site seed. **Last rehearsed**: not yet (vault empty at go-live); rehearse before the first real folder lands.

## Before you start

- Other peers hold full replicas; this node is the always-on introducer and backup source. While it is down they sync among themselves.
- If the identity is **not** restored, every peer must re-pair; the vault still comes back from them.

## Steps

1. Fetch the archive; `tar -tzf` must list `config/cert.pem`, `config/key.pem`, `config/config.xml`, `vault/`.
2. `kubectl -n pim scale deploy syncthing --replicas=0`; wait for the pod to go.
3. Helper pod with PVCs `syncthing-config` at `/src/config` and `syncthing-vault` at `/src/vault`, root with `CHOWN`/`FOWNER`/`DAC_OVERRIDE`. Copy the archive in via `exec -i ... cat >`.
4. In the helper: `cd /src && tar -xzf /tmp/a.tar.gz -C /src && chown -R 1000:1000 /src/config /src/vault`.
5. Delete the helper; scale to 1; wait for Ready. The first start rebuilds the index (minutes for a large vault).

## Verify

- `curl -s http://<node>:30384/rest/noauth/health` → `{"status":"OK"}`.
- With the GUI credentials or API key: `GET /rest/system/status` shows the **same** device ID as before; `GET /rest/config/folders` lists `vault`; `GET /rest/config/options` still has `globalAnnounceEnabled`, `relaysEnabled`, `natEnabled` false.
- A peer reconnects without re-pairing.

## Rollback

- Fresh PVCs give a new identity; re-pair peers. Nothing is lost that the peers hold.

## Failure modes seen

- 2026-09-30: first backup torn because `config.xml`/`key.pem` are `0600` uid 1000 and the ship container had no read capability. `DAC_READ_SEARCH` fixed it; the receiver rejected the torn archive as designed.
