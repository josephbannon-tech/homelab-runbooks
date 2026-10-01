# Restore a Proxmox guest from a vzdump archive

**What is protected**: whole VM/LXC images from the weekly vzdump job to the NAS-backed storage (retention set on the **storage** via `prune-backups`; a job-level `maxfiles` is ignored on current Proxmox). Guests with passthrough disks carry `backup=0` on those disks; pool data comes back via `zpool import`, not vzdump. **Last rehearsed**: 2026-09-08, an LXC restored into a spare CT id in 31 s, service proven inside.

## Before you start

- Restore into a **spare id** (e.g. 905), never over the live guest.
- The restored copy must not join the network with the live guest's identity: `link_down=1` for an LXC, `--unique` for a VM (regenerates MACs/UUIDs), `--onboot 0`, no `startup` order. A restored DHCP/DNS server with its NIC up would hand out leases.

## Steps

1. Pick the archive: `ls -t /mnt/nas-backups/dump/vzdump-*-<vmid>-*.{tar.zst,vma.zst} | head -1`.
2. LXC:

   ```bash
   pct restore 905 <archive> --storage local-lvm --unprivileged 1 --onboot 0 --hostname <name>-drill --description "restore DRILL <date> - destroy after"
   pct set 905 --net0 name=eth0,bridge=vmbr0,link_down=1,...   # before starting
   pct start 905; pct exec 905 -- <service check>
   ```

   VM:

   ```bash
   qmrestore <archive> 905 --storage local-lvm --unique 1
   qm set 905 --onboot 0 --net0 virtio=<MAC>,bridge=vmbr0,link_down=1 --delete startup
   qm start 905   # check via the console, not SSH
   ```

3. Prove the service inside (the restore is not done when the guest boots; it is done when the service answers).
4. Destroy the drill guest: `pct destroy 905 --purge` / `qm destroy 905 --purge`.
5. Log it (date, guest, archive, seconds, result) in the drill table.

## Verify

- Service-specific: for a DNS guest, `dig @<console-ip>`; for a game server, the port listens; for a VM, the guest agent answers (`qm agent 905 ping`), which also tells you whether `tailscaled` came up in a link-down copy (open question from drill 1).

## Rollback

- Nothing to roll back; the live guest was never touched.

## Failure modes seen

- Rehearsal with the NIC up risks a rogue DHCP server. Always `link_down=1` first.
