#!/bin/bash

# Script to view detailed eviction events
# Shows individual pod names instead of aggregated counts

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Pod Eviction Event Details"
echo "=========================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} kubectl is not installed"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}[WARN]${NC} jq is not installed. Some features will be limited."
    echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
    echo ""
    JQ_AVAILABLE=false
else
    JQ_AVAILABLE=true
fi

echo -e "${GREEN}=== 1. All Evicted Pods (Current Status) ===${NC}"
echo ""
kubectl get pods --all-namespaces --field-selector=status.phase=Failed 2>/dev/null || echo "No evicted pods found"
echo ""

echo -e "${GREEN}=== 2. Recent Eviction Events (Last 10) ===${NC}"
echo ""
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  --sort-by='.lastTimestamp' \
  -o custom-columns=\
'TIME:.lastTimestamp,NAMESPACE:.involvedObject.namespace,POD_NAME:.involvedObject.name,COUNT:.count,MESSAGE:.message' | tail -11
echo ""

echo -e "${GREEN}=== 3. Detailed Event Breakdown ===${NC}"
echo ""

if [ "$JQ_AVAILABLE" = true ]; then
    echo -e "${BLUE}Individual eviction events with full details:${NC}"
    echo ""
    kubectl get events --all-namespaces -o json 2>/dev/null | \
      jq -r '.items[] | select(.reason=="Evicted") | 
      "[\(.lastTimestamp)] \(.involvedObject.namespace)/\(.involvedObject.name)
      └─ Reason: \(.reason)
      └─ Count: \(.count // 1)
      └─ Message: \(.message)
      └─ Source: \(.source.component)
      "' | head -50
else
    echo "Install jq for detailed JSON parsing"
    kubectl get events --all-namespaces -o wide | grep Evicted | head -10
fi
echo ""

echo -e "${GREEN}=== 4. Event Sources Breakdown ===${NC}"
echo ""
kubectl get events --all-namespaces -o custom-columns=\
'SOURCE:.source.component,POD:.involvedObject.name,REASON:.reason' | \
grep -i evicted | head -10 || echo "No events found"
echo ""

echo -e "${GREEN}=== 5. Karpenter-Related Events ===${NC}"
echo ""
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | \
  grep -iE "karpenter|consolidat|disrupt" | tail -10 || echo "No Karpenter events found"
echo ""

echo -e "${GREEN}=== 6. Node Conditions ===${NC}"
echo ""
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,MEMORY_PRESSURE:.status.conditions[?(@.type=="MemoryPressure")].status,DISK_PRESSURE:.status.conditions[?(@.type=="DiskPressure")].status,PID_PRESSURE:.status.conditions[?(@.type=="PIDPressure")].status'
echo ""

echo -e "${YELLOW}=== Summary ===${NC}"
echo ""
EVICTED_COUNT=$(kubectl get events --all-namespaces --field-selector reason=Evicted 2>/dev/null | grep -v "LAST SEEN" | wc -l | xargs)
FAILED_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase=Failed 2>/dev/null | grep -v "NAMESPACE" | wc -l | xargs)

echo "• Total eviction events: $EVICTED_COUNT"
echo "• Currently failed/evicted pods: $FAILED_PODS"
echo ""

if [ "$EVICTED_COUNT" -gt "0" ]; then
    echo -e "${BLUE}To see more details about a specific pod:${NC}"
    echo "  kubectl describe pod <pod-name> -n <namespace>"
    echo ""
fi

echo "=========================================="
echo "Tip: Run this script periodically to monitor evictions"
echo "=========================================="

