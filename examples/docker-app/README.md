# Docker App Example

A Docker-based CF application using `nginxinc/nginx-unprivileged:1.27`.

This demonstrates pushing a pre-built Docker image to Cloud Foundry instead of
using a buildpack.

## Prerequisites

- Cloud Foundry is running (`make up`)
- You are logged in (`make login`)
- Bootstrap is complete (`make bootstrap`)
- Docker support is enabled (done automatically by `make bootstrap`)

## Push

```bash
cf push -f examples/docker-app/manifest.yaml
```

## Verify

```bash
curl http://docker-nginx.apps.127-0-0-1.nip.io
```

You should see the default nginx welcome page.

## How It Works

The `manifest.yaml` specifies `docker.image` instead of a `path`. CF pulls the
Docker image directly and runs it. The `nginx-unprivileged` variant is used
because CF containers run as a non-root user.

## Clean Up

```bash
cf delete -f docker-nginx
```
