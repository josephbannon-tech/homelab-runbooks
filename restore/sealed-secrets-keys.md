# Restore or rotate the Sealed Secrets sealing keys

**What is protected**: every sealing key the controller has ever used (it renews monthly and keeps the old ones active; each committed `SealedSecret` decrypts only with the key that was current when it was sealed). **Why it matters**: without the full set, secrets in Git are permanently undecryptable on a cluster rebuild.
**Source**: a nightly export of all keys from the cluster (`kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml`) to the operations host, rsynced to the NAS, in the off-site seed. **Last rehearsed**: 2026-09-09, `kubeseal --recovery-unseal` decrypted 7 of 7 committed files.

## Before you start

- On a rebuild, restore the keys **before** applying the app-of-apps, or every secret-bearing app fails and the controller mints a fresh key that decrypts nothing from Git.

## Steps

1. Confirm the backup holds every key: `grep -c 'kind: Secret' master-key-backup.yaml` should equal the number of keys the old cluster had (one per month since install). Compare the nightly copy and any manual copy with `md5sum`.
2. `kubectl create namespace kube-system --dry-run=client -o yaml | kubectl apply -f -`
3. `kubectl apply -f master-key-backup.yaml`
4. Install the controller (Helm or the app-of-apps); it picks up the restored keys.

## Verify

```bash
for f in charts/secrets/*.yaml; do kubeseal --recovery-unseal --recovery-private-key master-key-backup.yaml < "$f" >/dev/null && echo "ok $f" || echo "FAIL $f"; done
```

Expected: `ok` for every file.

## Rotation watch

- The controller mints a new key monthly. The nightly export runs at a fixed local time; a key minted after that time shows up in the next night's file. The drill: the morning after a renewal, the cluster count is N+1 and the backup still N; the morning after that, both N+1.

## Failure modes seen

- 2026-09-08: the export had been taken once, by hand, with one key; three of seven secrets could not decrypt. The nightly re-export and this verify loop are the fix.
