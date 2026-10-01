# Restore the Immich database (CloudNativePG)

**What is protected**: the Postgres database `immich` (albums, people, favourites, metadata the files cannot re-derive), as a nightly `pg_dump -Fc`. **Not**: the originals (NAS dataset over NFS, their own copy policy), thumbnails, encoded video, ML cache (all derivable).
**Source**: NAS `backups/immich-db/immich-db-<stamp>.tar.gz` containing `immich-<stamp>.dump`, 14 generations, nightly 02:45; heartbeat `name="immich-db-backup"`; in the off-site seed. **Last rehearsed**: 2026-10-01 into a scratch database on the live cluster: same 71 tables, user count and admin as live, 14 s.

## Before you start
- A real restore replaces the live database: stop the server first (`kubectl -n immich scale deploy immich-server --replicas=0`; it sticks, operator-owned replicas).
- The CNPG pod's root filesystem is read-only; stage the dump under the data volume.

## Steps
1. Fetch and unpack: `scp nas:/mnt/.../backups/immich-db/immich-db-<stamp>.tar.gz /tmp/ && tar -xzf /tmp/immich-db-<stamp>.tar.gz -C /tmp/`.
2. Copy into the Postgres pod: `kubectl -n immich exec -i immich-postgres-1 -c postgres -- sh -c 'cat > /var/lib/postgresql/data/restore.dump' < /tmp/immich-<stamp>.dump`.
3. In the pod as `postgres` (target `immich_restore` for a rehearsal, `immich` for real; for real, `DROP DATABASE immich` only after the server is stopped):
   ```bash
   psql -U postgres -c "CREATE DATABASE <db> OWNER immich"
   psql -U postgres -d <db> -c 'CREATE EXTENSION IF NOT EXISTS vchord CASCADE; CREATE EXTENSION IF NOT EXISTS cube; CREATE EXTENSION IF NOT EXISTS earthdistance; CREATE EXTENSION IF NOT EXISTS pg_trgm; CREATE EXTENSION IF NOT EXISTS unaccent; CREATE EXTENSION IF NOT EXISTS "uuid-ossp";'
   pg_restore -U postgres -d <db> --no-owner --no-acl --exit-on-error /var/lib/postgresql/data/restore.dump
   ```
   Expected: no output from `pg_restore` (a `NOTICE` about the `vector` extension is fine).
4. `rm /var/lib/postgresql/data/restore.dump`. For real: scale the server back up.

## Verify
```sql
select count(*) from pg_tables where schemaname='public';   -- 71 on v3.2
select count(*) from "user"; select count(*) from asset;
select email from "user" where "isAdmin";
```
Then the server's `/api/server/ping` and a login. Immich checks the `.immich` markers under its media location on start; if the originals volume moved too, see the media-location note in the gitops chart README.

## Rollback
- For a rehearsal: `DROP DATABASE immich_restore`. For real: the previous dump is one generation back.

## Failure modes seen
- 2026-10-01: `cat > /tmp/...` in the CNPG pod fails (read-only rootfs) → use the data volume path.
