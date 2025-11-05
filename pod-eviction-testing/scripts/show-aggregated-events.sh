#!/bin/bash

# Script to show events in AGGREGATED format (like "4 Evicted: Evicted pod")
# This mimics what monitoring tools and event aggregators display

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Kubernetes Event Aggregation View"
echo "=========================================="
echo ""

echo -e "${CYAN}This shows how events are aggregated/merged${NC}"
echo -e "${CYAN}(like what you see in monitoring tools)${NC}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} kubectl is not installed"
    exit 1
fi

echo -e "${GREEN}=== Method 1: Standard kubectl get events ===${NC}"
echo -e "${BLUE}(Shows Count column - this is the aggregation)${NC}"
echo ""

# Standard view - shows aggregation
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20
echo ""

echo -e "${GREEN}=== Method 2: Filtered for Eviction Events Only ===${NC}"
echo ""

# Get eviction events with count
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  --sort-by='.lastTimestamp' 2>/dev/null || echo "No eviction events found"
echo ""

echo -e "${GREEN}=== Method 3: Aggregated Summary (Like Monitoring Tools) ===${NC}"
echo ""

# Count by reason and type
echo -e "${BLUE}Event aggregation by Reason:${NC}"
kubectl get events --all-namespaces -o json 2>/dev/null | \
  jq -r '.items[] | "\(.reason)"' | sort | uniq -c | sort -rn || \
  echo "Install jq for better formatting: brew install jq"
echo ""

# Specific to evictions - show aggregated count
echo -e "${BLUE}Eviction Events Summary:${NC}"
EVICTED_EVENTS=$(kubectl get events --all-namespaces --field-selector reason=Evicted -o json 2>/dev/null)

if command -v jq &> /dev/null; then
    # Count total eviction events
    TOTAL_COUNT=$(echo "$EVICTED_EVENTS" | jq '[.items[].count // 1] | add // 0')
    UNIQUE_PODS=$(echo "$EVICTED_EVENTS" | jq '[.items[].involvedObject.name] | unique | length')
    
    echo "  Total Eviction Event Count: $TOTAL_COUNT"
    echo "  Unique Pods Evicted: $UNIQUE_PODS"
    echo ""
    
    # Show aggregated format
    echo -e "${YELLOW}Aggregated Format (what you see in monitors):${NC}"
    echo "  $TOTAL_COUNT Evicted: Evicted pod"
    echo ""
    
    # Break down by namespace
    echo -e "${BLUE}Breakdown by namespace:${NC}"
    echo "$EVICTED_EVENTS" | jq -r '.items[] | "\(.involvedObject.namespace)"' | sort | uniq -c | \
      awk '{printf "  %s evictions in namespace: %s\n", $1, $2}'
else
    # Fallback without jq
    TOTAL=$(kubectl get events --all-namespaces --field-selector reason=Evicted 2>/dev/null | grep -v "LAST SEEN" | wc -l | xargs)
    echo "  Total Eviction Events: $TOTAL"
    echo "  $TOTAL Evicted: Evicted pod"
fi
echo ""

echo -e "${GREEN}=== Method 4: Show Count Field Explicitly ===${NC}"
echo -e "${BLUE}(The 'Count' column shows how many times the event occurred)${NC}"
echo ""

kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o custom-columns=\
'COUNT:.count,REASON:.reason,TYPE:.type,NAMESPACE:.involvedObject.namespace,POD:.involvedObject.name,FIRST_SEEN:.firstTimestamp,LAST_SEEN:.lastTimestamp' \
  2>/dev/null || echo "No eviction events found"
echo ""

echo -e "${GREEN}=== Method 5: Datadog/Monitoring Style Aggregation ===${NC}"
echo ""

if command -v jq &> /dev/null; then
    echo -e "${BLUE}Events grouped by message (shows aggregation):${NC}"
    kubectl get events --all-namespaces -o json 2>/dev/null | \
      jq -r '.items[] | select(.reason=="Evicted") | .message' | \
      sort | uniq -c | sort -rn | head -5 | \
      awk '{count=$1; $1=""; printf "  %d events: %s\n", count, $0}'
    echo ""
fi

echo -e "${YELLOW}=== Understanding Event Aggregation ===${NC}"
echo ""
echo "Kubernetes automatically merges similar events:"
echo ""
echo "  Instead of showing:"
echo "    • Event 1: Pod A evicted"
echo "    • Event 2: Pod B evicted"
echo "    • Event 3: Pod C evicted"
echo "    • Event 4: Pod D evicted"
echo ""
echo "  It shows:"
echo "    • 4 Evicted: Evicted pod (Count: 4)"
echo ""
echo "The 'Count' field tells you how many times similar events occurred."
echo ""

echo -e "${CYAN}To see individual pod names (de-aggregated view), run:${NC}"
echo "  ./check-eviction-details.sh"
echo ""

echo "=========================================="

