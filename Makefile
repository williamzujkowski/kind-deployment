LOCAL = true
TARGET_ARCH ?= $(if $(filter true,$(LOCAL)),$(shell go env GOARCH),amd64)

init: temp/certs/ca.key temp/certs/ca.crt temp/certs/ssh_key temp/certs/ssh_key.pub temp/secrets.sh

temp/certs/ca.key temp/certs/ca.crt temp/certs/ssh_key temp/certs/ssh_key.pub temp/secrets.sh:
	@ ./scripts/init.sh

install:
	@ . temp/secrets.sh; \
	helmfile sync

login:
	@ . temp/secrets.sh; \
	cf login -a https://api.127-0-0-1.nip.io -u ccadmin -p "$$CC_ADMIN_PASSWORD" --skip-ssl-validation

create-kind:
	@ ./scripts/create-kind.sh

delete-kind:
	@ ./scripts/delete-kind.sh

create-org:
	cf create-org test
	cf create-space -o test test
	cf target -o test -s test
	@ ./scripts/set_feature_flags.sh

bootstrap: create-org
	@ ./scripts/upload_buildpacks.sh

bootstrap-complete: create-org 
	@ ALL_BUILDPACKS=true ./scripts/upload_buildpacks.sh

up: create-kind init install

down: delete-kind

smoke:
	@ chmod +x examples/smoke-test.sh
	@ ./examples/smoke-test.sh

verify:
	@ echo "Verifying CF API is reachable..."
	@ curl -sk --max-time 10 https://api.127-0-0-1.nip.io/v3/info | jq -r '.build' || { echo "FAIL: CF API not reachable"; exit 1; }
	@ echo "Pushing hello-js for verification..."
	@ cf push verify-hello-js -p examples/hello-js -m 1024M --random-route
	@ echo "Verifying app is running..."
	@ cf app verify-hello-js | grep "#0" | grep running
	@ echo "Cleaning up..."
	@ cf delete -f verify-hello-js
	@ echo "Verification complete."

status:
	@ echo "=== KIND Cluster ==="
	@ kind get clusters 2>/dev/null | grep cfk8s && echo "Cluster: cfk8s (exists)" || echo "Cluster: cfk8s (NOT FOUND)"
	@ echo ""
	@ echo "=== Node Status ==="
	@ kubectl get nodes 2>/dev/null || echo "kubectl not connected"
	@ echo ""
	@ echo "=== CF API Health ==="
	@ curl -sk --max-time 5 https://api.127-0-0-1.nip.io/v3/info | jq -r '"CF API build: " + .build' 2>/dev/null || echo "CF API: NOT REACHABLE"
	@ echo ""
	@ echo "=== Pod Summary ==="
	@ kubectl get pods -A --no-headers 2>/dev/null | awk '{status[$$4]++} END {for (s in status) printf "  %-20s %d\n", s, status[s]}' || echo "Cannot retrieve pods"
	@ echo ""
	@ echo "=== Non-Running Pods ==="
	@ kubectl get pods -A --no-headers 2>/dev/null | grep -v Running | grep -v Completed || echo "  All pods are Running or Completed"

PHONY: install login create-kind delete-kind up down create-org bootstrap bootstrap-complete smoke verify status
