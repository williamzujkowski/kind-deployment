# Quickstart Guide

Deploy Cloud Foundry locally on KIND in under 15 minutes.

---

## Prerequisites

Install all required tools before proceeding. Versions listed are the minimum
known-good versions from upstream CI.

| Tool       | Version    | Install Link                                                                 |
| ---------- | ---------- | ---------------------------------------------------------------------------- |
| Docker     | 24+        | https://docs.docker.com/get-docker/                                          |
| KIND       | v0.30.0+   | https://kind.sigs.k8s.io/docs/user/quick-start/#installing-from-release-binaries |
| Helm       | 3.x        | https://helm.sh/docs/intro/install/                                          |
| Helmfile   | v1.2.3+    | https://helmfile.readthedocs.io/en/latest/#installation                      |
| CF CLI     | v8+        | https://github.com/cloudfoundry/cli/releases                                 |
| kubectl    | 1.28+      | https://kubernetes.io/docs/tasks/tools/#kubectl                              |
| jq         | 1.6+       | https://jqlang.github.io/jq/download/                                       |
| openssl    | 1.1+       | Usually pre-installed on macOS/Linux                                         |
| make       | 3.81+      | Pre-installed on macOS/Linux                                                 |

### Docker Resource Allocation

Allocate at least **12 GB of RAM** to Docker. On Docker Desktop:

Settings -> Resources -> Memory: 12 GB (16 GB recommended)

Verify Docker is running:

```bash
docker info | grep "Total Memory"
#  Total Memory: 15.61GiB
```

### Verify Tool Versions

```bash
kind version
# kind v0.30.0 ...

helmfile version
# helmfile version v1.2.3 ...

cf version
# cf version 8.14.1 ...

helm version --short
# v3.x.x ...
```

---

## Step 1: Clone and Enter the Repository

```bash
git clone https://github.com/williamzujkowski/kind-deployment.git
cd kind-deployment
git checkout feature/local-full-workloads
```

---

## Step 2: Create Cluster and Install CF

```bash
make up
```

This single command does three things in sequence:

1. **`create-kind`** -- Creates a 3-node KIND cluster named `cfk8s`, sets up
   pull-through registry caches, installs Cilium CNI, applies cell node taints,
   and patches CoreDNS.
2. **`init`** -- Generates CA certificates, SSH keys, and random secrets into
   the `temp/` directory.
3. **`install`** -- Runs `helmfile sync` to deploy all infrastructure and CF
   components.

**Expected timing:**

| Run      | Duration     |
| -------- | ------------ |
| First    | 5-20 minutes |
| Cached   | 2-7 minutes  |

**Expected output (tail):**

```
Creating kind cluster 'cfk8s' ...
Setting up registry caches...
Configuring cache docker-io on all nodes...
Configuring cache ghcr-io on all nodes...
Configuring cache quay-io on all nodes...
...
Waiting for nodes to become ready after CNI installation...
node/cfk8s-control-plane condition met
node/cfk8s-worker condition met
node/cfk8s-worker2 condition met
...
UPDATED RELEASES:
  cert-manager  cert-manager  ...
  nats          default       ...
  istio-base    istio-system  ...
  istiod        istio-system  ...
  postgresql    default       ...
  minio         default       ...
  uaa           default       ...
  ...
```

Verify the cluster is healthy:

```bash
kubectl get nodes
# NAME                  STATUS   ROLES           AGE   VERSION
# cfk8s-control-plane   Ready    control-plane   Xm    v1.33.x
# cfk8s-worker          Ready    <none>          Xm    v1.33.x
# cfk8s-worker2         Ready    <none>          Xm    v1.33.x
```

---

## Step 3: Log In to Cloud Foundry

```bash
make login
```

**Expected output:**

```
API endpoint: https://api.127-0-0-1.nip.io
Authenticating...
OK
...
```

This logs in as the `ccadmin` user using the generated password from
`temp/secrets.sh`. The `--skip-ssl-validation` flag is used because the
deployment uses a self-signed CA.

---

## Step 4: Bootstrap (Create Org/Space + Upload Buildpacks)

```bash
make bootstrap
```

This creates a `test` org and `test` space, sets feature flags (enables Docker
and CNB support), and uploads the most common buildpacks (Java, Node.js, Go,
Binary).

For all buildpacks (including Ruby, Python, PHP, .NET, R, Nginx, Staticfile):

```bash
make bootstrap-complete
```

**Expected output:**

```
Creating org test...
Creating space test in org test...
Setting feature flags...
Uploading java-buildpack...
Uploading nodejs_buildpack...
Uploading go_buildpack...
Uploading binary_buildpack...
```

---

## Step 5: Push the Hello-JS Sample App

```bash
cf push -f examples/hello-js/manifest.yaml
```

**Expected output (tail):**

```
Staging app and tracing logs...
   ...
   -----> Node.js Buildpack
   ...
Waiting for app hello-js to start...
   ...
name:              hello-js
requested state:   started
routes:            hello-js.apps.127-0-0-1.nip.io
...
     state     since                  cpu    memory      disk
#0   running   2026-02-14T...   0.0%   xx.xM ...   xx.xM ...
```

Verify it responds:

```bash
curl http://hello-js.apps.127-0-0-1.nip.io
# Hello World! (CF_INSTANCE_INDEX: 0)
# Fibonacci(40): 102334155
```

---

## Step 6: Push a Docker App

Ensure Docker support is enabled (it is after `make bootstrap`):

```bash
cf push -f examples/docker-app/manifest.yaml
```

Verify:

```bash
curl http://docker-nginx.apps.127-0-0-1.nip.io
# (nginx welcome page HTML)
```

---

## Step 7: SSH Into an App

```bash
cf ssh hello-js
```

You will get a shell inside the running app container. Type `exit` to leave.

```
vcap@...:~$ ls app/
index.js  node_modules  package.json  Procfile
vcap@...:~$ exit
```

---

## Step 8: Clean Up

Tear down the entire deployment:

```bash
make down
```

This deletes the KIND cluster and stops the registry cache containers. Cached
images persist in Docker volumes for faster subsequent runs.

To also delete cached images:

```bash
docker volume ls --filter name=^cache_ -q | xargs docker volume rm
```

---

## Known-Good Resource Profile

These profiles have been tested:

| Profile          | RAM    | CPU     | Disk   | First Run  | Cached Run |
| ---------------- | ------ | ------- | ------ | ---------- | ---------- |
| Minimum          | 8 GB   | 4 cores | 10 GB  | 15-20 min  | 5-7 min    |
| Recommended      | 12 GB  | 4 cores | 15 GB  | 8-12 min   | 3-5 min    |
| Comfortable      | 16 GB  | 8 cores | 20 GB  | 5-8 min    | 2-3 min    |

---

## Optional: Disable Image Caching

If you do not want pull-through caches (e.g., testing cold-start):

```bash
DISABLE_CACHE=true make up
```

## Optional: Disable Components

```bash
# Without loggregator
ENABLE_LOGGREGATOR=false make up

# Without container networking / policy support
ENABLE_POLICY_SUPPORT=false make up
```

---

## Next Steps

- Run the smoke test suite: `make smoke`
- Check deployment status: `make status`
- Read the [Troubleshooting Guide](./TROUBLESHOOTING.md)
- Read the [Discovery Document](./discovery.md) for architecture details
