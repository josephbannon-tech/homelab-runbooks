# Stateful apps under GitOps self-heal

**Problem**: a restore wants the app scaled to zero while files are swapped. With ArgoCD `selfHeal` on, `kubectl scale --replicas=0` is reverted within about 30 seconds. Removing automated sync from the app's `Application` does not help when an app-of-apps owns that `Application`: the root re-applies the child's spec on its next sync. Both happened in one rehearsal (2026-09-30), once mid file swap.

## Fix in use: operator-owned replicas

On every app with PVC state, the `Application` carries:

```yaml
ignoreDifferences:
  - group: apps
    kind: StatefulSet   # or Deployment
    name: <workload>
    jsonPointers: ["/spec/replicas"]
syncPolicy:
  syncOptions:
    - RespectIgnoreDifferences=true
```

`RespectIgnoreDifferences` makes the ignore apply at sync time too, so replicas become operator-owned: a scale-down sticks until the operator scales back up. Trade-off: `replicaCount` in the chart values is no longer applied by ArgoCD for those apps. Fine when the design is one replica on SQLite or one CNPG instance.

Proof: scaled to 0, held for 60 s with the App still Synced/Healthy, scaled back; health 200.

## Fallback for an app without the rule

1. Remove `spec.syncPolicy.automated` on **both** the root `Application` and the app's `Application`.
2. Wait 30 s and confirm both still show no automated policy (root may have a new revision pending and sync anyway).
3. Scale down; confirm the pod stays gone for 30 s before touching data.
4. Restore, scale up, re-enable both, confirm Synced/Healthy.

## Also

- An app that starts during a DB file swap keeps a handle on the old inode. After the swap, restart the pod even if health is 200.
