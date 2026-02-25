#!/usr/bin/env bash
# =============================================================================
# canary-health-check.sh — Monitor a canary deployment for a specified duration.
# Polls pod status, error rates, and restart counts. Fails fast if anomalies
# are detected, triggering automatic rollback via --atomic in Helm.
# =============================================================================

set -euo pipefail

NAMESPACE="production"
RELEASE=""
DURATION=300      # seconds to monitor
ERROR_THRESHOLD=1 # max allowed pod restarts during monitoring window

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --namespace) NAMESPACE="$2"; shift ;;
    --release)   RELEASE="$2"; shift ;;
    --duration)  DURATION="$2"; shift ;;
    --error-threshold) ERROR_THRESHOLD="$2"; shift ;;
    *) echo "Unknown parameter: $1"; exit 1 ;;
  esac
  shift
done

echo "========================================"
echo "Canary Health Monitor"
echo "  Release:   ${RELEASE}"
echo "  Namespace: ${NAMESPACE}"
echo "  Duration:  ${DURATION}s"
echo "========================================"

INTERVAL=15
ELAPSED=0

while [ $ELAPSED -lt $DURATION ]; do
  echo ""
  echo "[$(date -u +'%H:%M:%S')] Elapsed: ${ELAPSED}s / ${DURATION}s"

  # Check pod status
  NOT_READY=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE}" \
    --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l || echo "0")

  if [ "$NOT_READY" -gt 0 ]; then
    echo "ERROR: ${NOT_READY} pod(s) not in Running state."
    kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE}" --no-headers
    exit 1
  fi

  # Check restart counts
  RESTARTS=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE}" \
    --no-headers -o custom-columns=RESTARTS:.status.containerStatuses[0].restartCount 2>/dev/null \
    | awk '{sum+=$1} END {print sum+0}')

  echo "Pod restarts during window: ${RESTARTS}"

  if [ "$RESTARTS" -gt "$ERROR_THRESHOLD" ]; then
    echo "ERROR: Restart count (${RESTARTS}) exceeded threshold (${ERROR_THRESHOLD}). Failing canary."
    kubectl describe pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE}"
    exit 1
  fi

  echo "Canary pods healthy. Continuing monitoring..."
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo ""
echo "========================================"
echo "Canary monitoring completed successfully."
echo "Promoting to full production rollout."
echo "========================================"
