#!/bin/bash

# Quick script to verify if event aggregation is from Kubernetes or monitoring tool

echo "=========================================="
echo "Event Aggregation Source Verification"
echo "=========================================="
echo ""

echo "Checking raw Kubernetes events..."
echo ""

# Count actual event objects in Kubernetes
EVENT_COUNT=$(kubectl get events --all-namespaces --field-selector reason=Evicted -o json 2>/dev/null | jq '.items | length' 2>/dev/null || echo "0")

echo "📊 Raw Kubernetes API has: $EVENT_COUNT separate event objects"
echo ""

if [ "$EVENT_COUNT" -gt 0 ]; then
    echo "Event details from Kubernetes:"
    echo ""
    kubectl get events --all-namespaces \
      --field-selector reason=Evicted \
      -o custom-columns='POD_NAME:.involvedObject.name,NAMESPACE:.involvedObject.namespace,COUNT:.count,TIMESTAMP:.lastTimestamp' 2>/dev/null | head -10
    echo ""
    
    echo "🔍 Interpretation:"
    echo ""
    
    # Check if events are for different pods
    UNIQUE_PODS=$(kubectl get events --all-namespaces --field-selector reason=Evicted -o json 2>/dev/null | jq '[.items[].involvedObject.name] | unique | length' 2>/dev/null || echo "0")
    
    echo "   • Total event objects in K8s: $EVENT_COUNT"
    echo "   • Unique pods evicted: $UNIQUE_PODS"
    echo ""
    
    if [ "$EVENT_COUNT" -eq "$UNIQUE_PODS" ]; then
        echo "   ✅ Each pod has 1 event → K8s stored them separately"
        echo "   ✅ The '4 Evicted' you saw is from your MONITORING TOOL"
        echo "   ✅ Kubernetes did NOT merge these events"
    else
        echo "   ⚠️  Some pods have multiple events → K8s merged same-pod events"
        echo "   ⚠️  Check COUNT column to see merged events"
    fi
else
    echo "No eviction events found in Kubernetes."
    echo "Events may have expired (default TTL: 1 hour)"
fi

echo ""
echo "=========================================="
echo "Answer: Where does '4 Evicted' come from?"
echo "=========================================="
echo ""
echo "If you saw '4 Evicted: Evicted pod' with this format:"
echo "  → It's from your MONITORING TOOL (Datadog, etc.)"
echo "  → NOT from Kubernetes events directly"
echo ""
echo "Kubernetes stores events like:"
echo "  pod-1 Evicted (COUNT: 1)"
echo "  pod-2 Evicted (COUNT: 1)"
echo "  pod-3 Evicted (COUNT: 1)"
echo "  pod-4 Evicted (COUNT: 1)"
echo ""
echo "Monitoring tools aggregate and show:"
echo "  '4 Evicted: Evicted pod'"
echo ""

