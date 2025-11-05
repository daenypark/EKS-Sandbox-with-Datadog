# Kubernetes Event Aggregation - Where Does It Happen?

## TL;DR Answer

The format you saw: **"4 Evicted: Evicted pod"** is likely from your **monitoring tool (Datadog, Prometheus, etc.)**, NOT directly from Kubernetes events.

**Here's why:**

---

## How Kubernetes Events Actually Work

### 1. Kubernetes Native Events (No Aggregation for Different Pods)

When 4 **different pods** are evicted, Kubernetes creates **4 separate event objects**:

```bash
# Raw Kubernetes events (4 separate events)
kubectl get events --all-namespaces --field-selector reason=Evicted -o json
```

Output (simplified):
```json
{
  "items": [
    {
      "involvedObject": {"name": "pod-1"},
      "reason": "Evicted",
      "count": 1,
      "message": "Pod evicted due to..."
    },
    {
      "involvedObject": {"name": "pod-2"},
      "reason": "Evicted",
      "count": 1,
      "message": "Pod evicted due to..."
    },
    {
      "involvedObject": {"name": "pod-3"},
      "reason": "Evicted",
      "count": 1,
      "message": "Pod evicted due to..."
    },
    {
      "involvedObject": {"name": "pod-4"},
      "reason": "Evicted",
      "count": 1,
      "message": "Pod evicted due to..."
    }
  ]
}
```

☝️ **4 separate event objects** - Kubernetes does NOT merge them!

---

### 2. When Kubernetes DOES Merge Events (Same Pod)

Kubernetes only merges events for the **SAME pod** with the **SAME reason**:

```bash
# If pod-1 is evicted multiple times (e.g., in a loop)
```

```json
{
  "involvedObject": {"name": "pod-1"},
  "reason": "Evicted",
  "count": 4,  // ← Incremented count
  "firstTimestamp": "2025-10-17T02:06:19Z",
  "lastTimestamp": "2025-10-17T02:08:45Z",
  "message": "Pod evicted due to..."
}
```

☝️ **Single event with count=4** - This means pod-1 was evicted 4 times

---

## Where Your "4 Evicted" Message Comes From

### Option A: Monitoring Tool Aggregation (Most Likely)

Tools like **Datadog, Grafana, Prometheus Alertmanager** aggregate events:

```
Datadog receives:
  - Event 1: pod-1 evicted
  - Event 2: pod-2 evicted  
  - Event 3: pod-3 evicted
  - Event 4: pod-4 evicted

Datadog shows:
  "4 Evicted: Evicted pod"
  (Grouped by reason="Evicted")
```

This is **NOT** from Kubernetes - it's the monitoring tool grouping similar events!

### Option B: Karpenter Event Aggregation

If you saw this in Karpenter logs/events:

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
```

Karpenter might log: "Evicted 4 pods from node-xyz"

This is Karpenter's **summary message**, not individual Kubernetes events.

### Option C: kubectl Event Summary

Running:
```bash
kubectl get events --all-namespaces
```

Shows:
```
LAST SEEN   TYPE      REASON    OBJECT        MESSAGE                  COUNT
2m ago      Warning   Evicted   pod/pod-1     Pod evicted...           1
2m ago      Warning   Evicted   pod/pod-2     Pod evicted...           1
2m ago      Warning   Evicted   pod/pod-3     Pod evicted...           1
2m ago      Warning   Evicted   pod/pod-4     Pod evicted...           1
```

☝️ Each line is a **separate event** (COUNT=1 for each)

---

## Testing This Yourself

Let me show you the difference:

### Test 1: Multiple Different Pods Evicted (No K8s Merging)

```bash
# Deploy 4 pods that will be evicted
kubectl apply -f eviction-test-multiple.yaml

# Wait for evictions (~10s)
sleep 12

# Check raw Kubernetes events (JSON format)
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o json | jq '.items | length'

# Output: 4
# ☝️ Four separate event objects in Kubernetes

# Check each event's count field
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o custom-columns='POD:.involvedObject.name,COUNT:.count'

# Output:
# POD                         COUNT
# multi-pod-eviction-test-1   1
# multi-pod-eviction-test-2   1
# multi-pod-eviction-test-3   1
# multi-pod-eviction-test-4   1
```

☝️ **Kubernetes stored 4 separate events, each with COUNT=1**

---

### Test 2: Same Pod Evicted Multiple Times (K8s WILL Merge)

```bash
# Create a pod that gets evicted and recreated in a loop
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: repeated-eviction-test
spec:
  restartPolicy: Always  # ← Will recreate after eviction
  containers:
  - name: storage-filler
    image: busybox
    command: ["/bin/sh", "-c", "while true; do dd if=/dev/zero of=/tmp/f bs=1M count=500; done"]
    resources:
      limits:
        ephemeral-storage: "100Mi"
EOF

# Wait for multiple eviction cycles (~30s)
sleep 30

# Check the event for this specific pod
kubectl get events --field-selector involvedObject.name=repeated-eviction-test \
  -o custom-columns='POD:.involvedObject.name,REASON:.reason,COUNT:.count,FIRST:.firstTimestamp,LAST:.lastTimestamp'

# Output:
# POD                        REASON    COUNT   FIRST                    LAST
# repeated-eviction-test     Evicted   3       2025-10-17T02:06:19Z    2025-10-17T02:06:45Z
```

☝️ **Single event with COUNT=3** - Kubernetes merged same-pod events!

---

## Summary Table

| Scenario | Kubernetes Behavior | Event Count |
|----------|-------------------|-------------|
| **4 different pods evicted once** | Creates 4 separate events | 4 events, each COUNT=1 |
| **1 pod evicted 4 times** | Creates 1 merged event | 1 event, COUNT=4 |
| **Monitoring tool display** | N/A - external aggregation | Shows "4 Evicted" |

---

## Where Did You See "4 Evicted: Evicted pod"?

### If you saw it in Datadog:

```
Events emitted by karpenter seen at 2025-10-17 02:06:19 +0000 UTC
4 Evicted: Evicted pod
```

**This is Datadog's aggregation!** Datadog groups similar events and shows the count.

Check the raw Kubernetes events:
```bash
# See what Kubernetes actually has
kubectl get events --all-namespaces --field-selector reason=Evicted
```

You'll likely see 4 separate event lines (or possibly fewer if they expired).

### If you saw it in Karpenter logs:

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep -i evict
```

Karpenter logs might say: "consolidation deleted node after evicting 4 pods"

This is Karpenter's **summary**, not Kubernetes events.

---

## Commands to Verify

### Check Raw Kubernetes Events (No External Aggregation)

```bash
# Method 1: Count actual event objects
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o json | jq '.items | length'

# Method 2: See each event's count field
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o custom-columns='POD:.involvedObject.name,COUNT:.count,MESSAGE:.message'

# Method 3: See if events are for same or different pods
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o custom-columns='POD:.involvedObject.name,NAMESPACE:.involvedObject.namespace,COUNT:.count' | sort
```

---

## The Answer to Your Question

> "So, the multiple eviction events are not from kube event right?"

**Correct!** The display format **"4 Evicted: Evicted pod"** is NOT how Kubernetes stores events.

**What actually happened:**

1. **Kubernetes created 4 separate event objects** (one per pod)
2. **Each event has COUNT=1**
3. **Your monitoring tool (Datadog/etc) aggregated them** for display
4. **It showed "4 Evicted"** by counting similar events

**Kubernetes native view:**
```bash
kubectl get events --field-selector reason=Evicted
```
```
OBJECT      REASON    MESSAGE                                    COUNT
pod/app-1   Evicted   Pod ephemeral storage usage exceeds...    1
pod/app-2   Evicted   Pod ephemeral storage usage exceeds...    1
pod/app-3   Evicted   Pod ephemeral storage usage exceeds...    1
pod/app-4   Evicted   Pod ephemeral storage usage exceeds...    1
```

**Monitoring tool view (Datadog/etc):**
```
4 Evicted: Evicted pod
```

---

## Key Takeaways

✅ **Kubernetes merges events ONLY for the same pod + same reason**
❌ **Kubernetes does NOT merge events for different pods**
✅ **Monitoring tools aggregate events for display**
✅ **"4 Evicted" = 4 different pods evicted (shown by monitoring tool)**
✅ **Each pod has its own event object in Kubernetes**

---

## Verification Script

Run this to see exactly what Kubernetes has:

```bash
echo "=== Raw Kubernetes Event Objects ==="
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o json | jq '.items | length'
echo "^ This is the actual number of event objects in Kubernetes"
echo ""

echo "=== Each Event's Details ==="
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o custom-columns='POD:.involvedObject.name,COUNT:.count,NAMESPACE:.involvedObject.namespace'
echo ""

echo "If you see 4 lines with COUNT=1 each → 4 different pods evicted (no K8s merging)"
echo "If you see 1 line with COUNT=4 → same pod evicted 4 times (K8s merged)"
```

