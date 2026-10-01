# First unattended night

Run the morning after any new backup job goes live. A manual run proves the pipeline; the first scheduled run proves the schedule, the timezone, and the off-site pickup.

1. Heartbeat age in Prometheus:

   ```promql
   (time() - backup_last_success_timestamp_seconds{name="<job>-backup"}) / 3600
   ```

   Expected: a few hours, matching the schedule in the job's timezone (CronJobs here run in `Europe/London`; the hypervisor and some containers run in UTC: a `01:45` cron on a UTC guest is `02:45` local in summer).
2. The archive on the NAS carries this morning's stamp and lists cleanly: `ls -t backups/<job>/ | head -2; tar -tzf <newest>`.
3. The off-site run that follows picked it up: `restic snapshots --tag <group> --latest 1 --json` lists the new archive's path.
4. The CronJob's `lastSuccessfulTime` is set: `kubectl get cronjob -A`.
5. Nothing fired overnight: the alert list shows only the watchdog.

Record the result on the TODO item that tracked the rollout, then delete the item.
