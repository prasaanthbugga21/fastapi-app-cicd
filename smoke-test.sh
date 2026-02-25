#!/usr/bin/env bash
# =============================================================================
# smoke-test.sh — Post-deployment smoke tests for FastAPI application
# Usage: bash scripts/smoke-test.sh <BASE_URL>
# =============================================================================

set -euo pipefail

BASE_URL="${1:?Usage: $0 <base_url>}"
MAX_RETRIES=10
RETRY_INTERVAL=10
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Wait for the application to become ready before running tests
wait_for_ready() {
  log_info "Waiting for application to become ready at ${BASE_URL}/healthz/ready ..."
  for i in $(seq 1 $MAX_RETRIES); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/healthz/ready" || true)
    if [ "$STATUS" == "200" ]; then
      log_info "Application is ready after ${i} attempt(s)."
      return 0
    fi
    log_info "Attempt ${i}/${MAX_RETRIES}: status=${STATUS}. Retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
  done
  log_fail "Application did not become ready after $((MAX_RETRIES * RETRY_INTERVAL))s."
  exit 1
}

# Run individual endpoint check
check_endpoint() {
  local description="$1"
  local url="$2"
  local expected_status="$3"
  local expected_body_contains="${4:-}"

  RESPONSE=$(curl -s -w "\n%{http_code}" "${url}" 2>/dev/null)
  HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n -1)

  if [ "$HTTP_STATUS" != "$expected_status" ]; then
    log_fail "${description} — Expected HTTP ${expected_status}, got ${HTTP_STATUS}"
    return
  fi

  if [ -n "$expected_body_contains" ] && ! echo "$BODY" | grep -q "$expected_body_contains"; then
    log_fail "${description} — Response body missing expected string: '${expected_body_contains}'"
    return
  fi

  log_pass "${description} (HTTP ${HTTP_STATUS})"
}

# ---- Main ----
echo ""
echo "=============================================="
echo "  Smoke Tests — ${BASE_URL}"
echo "=============================================="
echo ""

wait_for_ready

check_endpoint "Liveness probe"      "${BASE_URL}/healthz/live"    "200" "alive"
check_endpoint "Readiness probe"     "${BASE_URL}/healthz/ready"   "200" "ready"
check_endpoint "Root endpoint"       "${BASE_URL}/"                "200" "fastapi-app"
check_endpoint "List items"          "${BASE_URL}/api/v1/items"    "200" "items"
check_endpoint "Get item by ID"      "${BASE_URL}/api/v1/items/1"  "200" "id"
check_endpoint "Metrics endpoint"    "${BASE_URL}/metrics"         "200" "http_requests"
check_endpoint "Invalid item (422)"  "${BASE_URL}/api/v1/items/-1" "422"

echo ""
echo "=============================================="
echo "  Results: ${PASS} passed | ${FAIL} failed"
echo "=============================================="

if [ $FAIL -gt 0 ]; then
  echo -e "${RED}Smoke tests FAILED. Blocking deployment.${NC}"
  exit 1
fi

echo -e "${GREEN}All smoke tests passed.${NC}"
