#!/bin/sh
#
# Smoke test for Cloud Foundry KIND deployment.
# Pushes sample apps, verifies they work, then cleans up.
#
# Usage: ./examples/smoke-test.sh
# Note:  Make this file executable: chmod +x examples/smoke-test.sh

set -euo pipefail

# --- Color output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

pass() { printf "${GREEN}[PASS]${NC} %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; FAILURES=$((FAILURES + 1)); }
info() { printf "${YELLOW}[INFO]${NC} %s\n" "$1"; }

FAILURES=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Cleanup function ---
cleanup() {
  info "Cleaning up test apps..."
  cf delete -f smoke-hello-js 2>/dev/null || true
  cf delete -f smoke-docker-nginx 2>/dev/null || true
  cf delete -f smoke-worker-app 2>/dev/null || true
}
trap cleanup EXIT

# --- Pre-flight check ---
info "Checking CF CLI is logged in..."
if ! cf target > /dev/null 2>&1; then
  fail "CF CLI is not logged in. Run 'make login' first."
  exit 1
fi
pass "CF CLI is logged in"

ORG=$(cf target | grep "^org:" | awk '{print $2}')
SPACE=$(cf target | grep "^space:" | awk '{print $2}')
info "Target: org=${ORG} space=${SPACE}"

# --- Test 1: Push hello-js (buildpack app) ---
info "Pushing hello-js app..."
if cf push smoke-hello-js -p "${REPO_ROOT}/examples/hello-js" -m 1024M --no-route > /dev/null 2>&1; then
  cf map-route smoke-hello-js apps.127-0-0-1.nip.io --hostname smoke-hello-js > /dev/null 2>&1
  pass "hello-js app pushed"
else
  fail "hello-js app push failed"
fi

info "Verifying hello-js HTTP response..."
sleep 5
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "http://smoke-hello-js.apps.127-0-0-1.nip.io" 2>/dev/null || echo "000")
if [ "${HTTP_CODE}" = "200" ]; then
  pass "hello-js returned HTTP 200"
else
  fail "hello-js returned HTTP ${HTTP_CODE} (expected 200)"
fi

# --- Test 2: Push docker app ---
info "Pushing docker-nginx app..."
if cf push smoke-docker-nginx --docker-image nginxinc/nginx-unprivileged:1.27 -m 256M --no-route > /dev/null 2>&1; then
  cf map-route smoke-docker-nginx apps.127-0-0-1.nip.io --hostname smoke-docker-nginx > /dev/null 2>&1
  pass "docker-nginx app pushed"
else
  fail "docker-nginx app push failed"
fi

info "Verifying docker-nginx HTTP response..."
sleep 5
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "http://smoke-docker-nginx.apps.127-0-0-1.nip.io" 2>/dev/null || echo "000")
if [ "${HTTP_CODE}" = "200" ]; then
  pass "docker-nginx returned HTTP 200"
else
  fail "docker-nginx returned HTTP ${HTTP_CODE} (expected 200)"
fi

# --- Test 3: Push worker app ---
info "Pushing worker-app..."
if cf push smoke-worker-app -p "${REPO_ROOT}/examples/worker-app" -m 256M --no-route --health-check-type process -c "node worker.js" > /dev/null 2>&1; then
  pass "worker-app pushed"
else
  fail "worker-app push failed"
fi

info "Verifying worker-app is running..."
sleep 5
STATE=$(cf app smoke-worker-app 2>/dev/null | grep "^#0" | awk '{print $2}')
if [ "${STATE}" = "running" ]; then
  pass "worker-app is running"
else
  fail "worker-app state is '${STATE}' (expected 'running')"
fi

# --- Test 4: SSH access ---
info "Checking SSH access to hello-js app..."
if cf ssh smoke-hello-js -c "echo ssh-ok" 2>/dev/null | grep -q "ssh-ok"; then
  pass "SSH access works"
else
  fail "SSH access failed"
fi

# --- Test 5: cf logs ---
info "Checking cf logs for worker-app..."
LOG_OUTPUT=$(cf logs smoke-worker-app --recent 2>/dev/null || echo "")
if echo "${LOG_OUTPUT}" | grep -q "tick"; then
  pass "cf logs shows worker output"
else
  fail "cf logs did not show expected worker output"
fi

# --- Summary ---
echo ""
echo "==============================="
if [ "${FAILURES}" -eq 0 ]; then
  printf "${GREEN}All smoke tests passed.${NC}\n"
  echo "==============================="
  exit 0
else
  printf "${RED}${FAILURES} smoke test(s) failed.${NC}\n"
  echo "==============================="
  exit 1
fi
