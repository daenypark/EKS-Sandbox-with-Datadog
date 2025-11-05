#!/bin/bash

# Quick Eviction Test Script
# This script deploys a pod that will be evicted and monitors the process

set -e

echo "=========================================="
echo "Quick Pod Eviction Test for EKS"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if connected to cluster
if ! kubectl cluster-info &> /dev/null; then
    print_error "Not connected to any Kubernetes cluster"
    exit 1
fi

print_info "Connected to cluster: $(kubectl config current-context)"
echo ""

# Deploy the eviction test pod
print_info "Deploying eviction test pod..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: quick-eviction-test
  labels:
    app: eviction-test
spec:
  containers:
  - name: storage-filler
    image: busybox
    command:
    - /bin/sh
    - -c
    - |
      echo "Starting to fill ephemeral storage..."
      while true; do
        dd if=/dev/zero of=/tmp/fill-\$(date +%s) bs=1M count=100
        sleep 1
      done
    resources:
      limits:
        ephemeral-storage: "500Mi"
      requests:
        ephemeral-storage: "200Mi"
  restartPolicy: Never
EOF

echo ""
print_info "Pod deployed. Monitoring for eviction (this takes ~5-10 seconds)..."
echo ""

# Wait for pod to start
sleep 2

# Monitor pod status
print_info "Pod status:"
for i in {1..20}; do
    STATUS=$(kubectl get pod quick-eviction-test -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    REASON=$(kubectl get pod quick-eviction-test -o jsonpath='{.status.reason}' 2>/dev/null || echo "")
    
    echo "  [$i] Status: $STATUS | Reason: $REASON"
    
    if [ "$STATUS" = "Failed" ] || [ "$REASON" = "Evicted" ]; then
        echo ""
        print_info "✓ Pod has been EVICTED!"
        break
    fi
    
    sleep 1
done

echo ""
print_info "Pod details:"
kubectl describe pod quick-eviction-test

echo ""
print_info "Recent eviction events:"
kubectl get events --field-selector involvedObject.name=quick-eviction-test --sort-by='.lastTimestamp'

echo ""
print_info "All recent events (last 10):"
kubectl get events --sort-by='.lastTimestamp' | tail -10

echo ""
print_warning "Cleaning up test pod..."
kubectl delete pod quick-eviction-test --ignore-not-found

echo ""
print_info "Test complete!"
echo ""
echo "=========================================="
echo "To run manual tests, use:"
echo "  kubectl apply -f eviction-test-ephemeral.yaml"
echo "  kubectl apply -f eviction-test-memory.yaml"
echo "=========================================="

