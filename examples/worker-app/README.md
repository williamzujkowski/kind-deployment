# Worker App Example

A background worker process with no HTTP route. Logs a message every 5 seconds.

This demonstrates pushing a non-web process to Cloud Foundry using
`no-route: true` and `health-check-type: process`.

## Prerequisites

- Cloud Foundry is running (`make up`)
- You are logged in (`make login`)
- Bootstrap is complete (`make bootstrap`)

## Push

```bash
cf push -f examples/worker-app/manifest.yaml
```

## Verify

The worker has no HTTP route. Verify it is running:

```bash
cf app worker-app
# requested state:   started
# ...
# #0   running   ...
```

Check its logs:

```bash
cf logs worker-app --recent
# [APP/PROC/WEB/0] Worker started: worker-app instance 0
# [APP/PROC/WEB/0] [...] worker-app instance 0: tick #1
# [APP/PROC/WEB/0] [...] worker-app instance 0: tick #2
```

Or stream live:

```bash
cf logs worker-app
# (Ctrl+C to stop)
```

## Clean Up

```bash
cf delete -f worker-app
```
