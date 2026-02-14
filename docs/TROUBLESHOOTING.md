# Troubleshooting Guide

Common failure modes and their solutions for the Cloud Foundry KIND deployment.

---

## Docker Not Running / Insufficient Resources

**Symptom:** `make up` fails immediately with Docker connection errors.

```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

**Fix:**

1. Start Docker Desktop or the Docker daemon.
2. Verify Docker is running: `docker info`
3. Ensure at least 12 GB RAM is allocated to Docker:
   - Docker Desktop: Settings -> Resources -> Memory
   - Check: `docker info | grep "Total Memory"`

**Symptom:** Pods stuck in `Pending` with `Insufficient memory` events.

```bash
kubectl describe pod <pod-name> | grep -A5 Events
# Warning  FailedScheduling  Insufficient memory
```

**Fix:** Increase Docker memory allocation to 12-16 GB and recreate the cluster:

```bash
make down
# Adjust Docker Desktop memory settings
make up
```

---

## Image Pull Failures / Rate Limiting

**Symptom:** Pods stuck in `ImagePullBackOff` or `ErrImagePull`.

```bash
kubectl describe pod <pod-name> | grep -i "pull"
# Failed to pull image: toomanyrequests: You have reached your pull rate limit
```

**Fix:**

The pull-through caches should prevent this. Verify they are running:

```bash
docker ps --filter name=docker-io --filter name=ghcr-io --filter name=quay-io
```

If caches are not running, restart them:

```bash
docker compose -p cache -f scripts/docker-compose.yaml up -d
```

If you disabled caching with `DISABLE_CACHE=true`, either wait for the rate
limit to reset (usually 6 hours) or re-run without that flag:

```bash
make down
make up
```

For persistent issues, authenticate with Docker Hub:

```bash
docker login
```

---

## Port Conflicts (80, 443, 2222 Already in Use)

**Symptom:** KIND cluster creation fails with port binding errors.

```
Ports are not available: exposing port TCP 0.0.0.0:80 -> 127.0.0.1:31080
```

**Fix:**

Find what is using the port:

```bash
# Linux
sudo ss -tlnp | grep -E ':80 |:443 |:2222 '

# macOS
sudo lsof -iTCP:80 -sTCP:LISTEN
sudo lsof -iTCP:443 -sTCP:LISTEN
```

Common culprits:
- **Apache/Nginx** running locally: `sudo systemctl stop apache2 nginx`
- **Another KIND cluster:** `kind get clusters` and delete unused ones
- **Other containers:** `docker ps` and stop conflicting containers

---

## DNS Resolution Issues (nip.io Blocked)

**Symptom:** `cf push` or `curl` fails to resolve `*.127-0-0-1.nip.io`.

```
Could not resolve host: api.127-0-0-1.nip.io
```

**Fix:**

Some corporate DNS servers or VPNs block wildcard DNS services like nip.io.

Test DNS resolution:

```bash
nslookup hello-js.apps.127-0-0-1.nip.io
# Should resolve to 127.0.0.1
```

If it fails:

1. **Try a public DNS resolver:**

   ```bash
   nslookup hello-js.apps.127-0-0-1.nip.io 8.8.8.8
   ```

2. **If public DNS works, switch your resolver:**
   - Temporarily set DNS to `8.8.8.8` or `1.1.1.1`
   - On macOS: System Settings -> Network -> DNS
   - On Linux: edit `/etc/resolv.conf` or use `systemd-resolved`

3. **If behind a corporate VPN**, disconnect VPN or add manual `/etc/hosts`
   entries:

   ```
   127.0.0.1 api.127-0-0-1.nip.io
   127.0.0.1 login.127-0-0-1.nip.io
   127.0.0.1 uaa.127-0-0-1.nip.io
   127.0.0.1 hello-js.apps.127-0-0-1.nip.io
   127.0.0.1 docker-nginx.apps.127-0-0-1.nip.io
   ```

   Note: You must add an entry for every app route individually.

---

## Cilium / CNI Not Ready

**Symptom:** Nodes stuck in `NotReady` after cluster creation.

```bash
kubectl get nodes
# NAME                  STATUS     ROLES           AGE
# cfk8s-control-plane   NotReady   control-plane   5m
```

**Fix:**

Cilium installs after the KIND cluster is created. Wait for it:

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium-agent
```

If Cilium pods are in `CrashLoopBackOff`:

```bash
kubectl -n kube-system logs -l app.kubernetes.io/name=cilium-agent
```

Common causes:
- Insufficient memory (Cilium needs ~512 MB)
- Kernel version too old (need 4.19+): `uname -r`
- AppArmor/SELinux conflicts on certain Linux distros

To force a reinstall:

```bash
make down
make up
```

---

## Pods Stuck in Pending / CrashLoopBackOff

**Symptom:** CF component pods are `Pending` or `CrashLoopBackOff`.

### Check Pod Status

```bash
kubectl get pods -A | grep -v Running | grep -v Completed
```

### Pending Pods -- Check Events

```bash
kubectl describe pod <pod-name> | tail -20
```

Common causes:
- **Cell node taint:** Workload pods should only run on the cell node
  (`cloudfoundry.org/cell=true`). CF system pods should NOT have this toleration.
  If system pods are Pending, check for unexpected taints:

  ```bash
  kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
  ```

- **Resource limits:** The node may not have enough CPU/memory. Scale up Docker
  resources.

### CrashLoopBackOff -- Check Logs

```bash
kubectl logs <pod-name> --previous
```

Common causes:
- **Database not ready:** PostgreSQL must be healthy before UAA, CAPI, CredHub,
  and Locket can start. Helmfile `needs:` handles ordering, but if PostgreSQL is
  slow, dependent pods may crash and retry.

  ```bash
  kubectl get pods -l app.kubernetes.io/name=postgresql
  ```

- **Certificate issues:** If `temp/certs/` was corrupted or regenerated without
  a full redeploy, certificates may mismatch.

  ```bash
  # Full reset
  make down
  rm -rf temp/
  make up
  ```

---

## CoreDNS Rewrite Not Working

**Symptom:** Apps are deployed but `curl` to `*.apps.127-0-0-1.nip.io` times
out from within the cluster, even though external DNS resolves correctly.

**Fix:**

Verify the CoreDNS rewrite rule is present:

```bash
kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}'
```

You should see a line containing:

```
rewrite name regex (.*)\.127-0-0-1\.nip\.io istio-gateway-istio.default.svc.cluster.local answer auto
```

If missing, the CoreDNS patch in `scripts/create-kind.sh` may have failed.
Re-apply manually:

```bash
# Re-run the create-kind script's CoreDNS patch section
corefile=$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | sed '/kubernetes/i \
    rewrite name regex (.*)\\.127-0-0-1\\.nip\\.io istio-gateway-istio.default.svc.cluster.local answer auto\
')
kubectl -n kube-system patch configmap coredns --type=json \
  -p="$(jq -n --arg cf "$corefile" '[{"op":"replace","path":"/data/Corefile","value":$cf}]')"
kubectl -n kube-system rollout restart deployment/coredns
```

---

## CF Push Timeout

**Symptom:** `cf push` hangs during staging or times out downloading buildpacks.

```
Error staging application: ...timed out
```

**Fix:**

1. **Check the file-server is running:**

   ```bash
   kubectl get pods -l app=file-server
   ```

2. **Check buildpack download:** Buildpacks are served from the file-server at
   `http://file-server.127-0-0-1.nip.io/`. Verify it is accessible from inside
   the cluster:

   ```bash
   kubectl run curl --rm -it --image=curlimages/curl -- \
     curl -s -o /dev/null -w "%{http_code}" http://file-server.127-0-0-1.nip.io/
   ```

3. **Check staging logs:**

   ```bash
   cf logs <app-name> --recent
   ```

4. **Increase push timeout:**

   ```bash
   cf push -f manifest.yaml -t 300
   ```

5. **If the cell node is overloaded**, check its resource usage:

   ```bash
   kubectl top node
   kubectl top pods --sort-by=memory -A
   ```

---

## CF Login SSL Errors

**Symptom:** `cf login` fails with certificate errors.

```
x509: certificate signed by unknown authority
```

**Fix:**

Always use `--skip-ssl-validation` when logging in to the local deployment:

```bash
cf login -a https://api.127-0-0-1.nip.io --skip-ssl-validation
```

The `make login` target already includes this flag.

If you want to trust the CA instead:

```bash
# macOS
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain temp/certs/ca.crt

# Linux (Debian/Ubuntu)
sudo cp temp/certs/ca.crt /usr/local/share/ca-certificates/cfk8s-ca.crt
sudo update-ca-certificates
```

Then log in without `--skip-ssl-validation`:

```bash
cf login -a https://api.127-0-0-1.nip.io
```

---

## KIND Cluster Won't Delete Cleanly

**Symptom:** `make down` fails or `kind delete cluster` hangs.

```
ERROR: failed to delete cluster "cfk8s"
```

**Fix:**

1. **Force delete:**

   ```bash
   kind delete cluster --name cfk8s
   ```

2. **If that fails, remove Docker containers manually:**

   ```bash
   docker rm -f $(docker ps -a --filter name=cfk8s -q)
   ```

3. **Clean up Docker networks:**

   ```bash
   docker network rm kind 2>/dev/null || true
   ```

4. **Clean up cache containers:**

   ```bash
   docker compose -p cache -f scripts/docker-compose.yaml down
   ```

5. **Nuclear option -- restart Docker:**

   ```bash
   # macOS: Restart Docker Desktop
   # Linux:
   sudo systemctl restart docker
   ```

---

## Diagnostic Commands

Quick reference for investigating issues:

```bash
# Cluster status
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

# Events (sorted by time)
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# CF API health
curl -sk https://api.127-0-0-1.nip.io/v3/info | jq .

# Specific component logs
kubectl logs -l app.kubernetes.io/name=cloud-controller --tail=50
kubectl logs -l app.kubernetes.io/name=gorouter --tail=50
kubectl logs -l app.kubernetes.io/name=uaa --tail=50
kubectl logs -l app.kubernetes.io/name=diego-bbs --tail=50

# Node resource usage
kubectl top nodes
kubectl top pods --sort-by=memory -A | head -20

# Registry cache status
docker ps --filter name=docker-io --filter name=ghcr-io --filter name=quay-io

# CF target info
cf target
cf apps
cf buildpacks
```
