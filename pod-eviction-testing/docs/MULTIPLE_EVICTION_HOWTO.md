# Understanding Multiple Pod Evictions

## What You're Seeing

```
4 Evicted: Evicted pod
```

This means **4 SEPARATE PODS** were evicted, not 1 pod evicted 4 times!

---

## Quick Commands to See Individual Pods

### 1. See Which Specific Pods Were Evicted

```bash
# List all evicted/failed pods with names
kubectl get pods --all-namespaces --field-selector=status.phase=Failed
```

**Output example:**
```
NAMESPACE   NAME                              READY   STATUS    RESTARTS   AGE
default     eviction-test-multi-abc123-xyz    0/1     Evicted   0          2m
default     eviction-test-multi-def456-uvw    0/1     Evicted   0          2m
default     eviction-test-multi-ghi789-rst    0/1     Evicted   0          2m
default     eviction-test-multi-jkl012-opq    0/1     Evicted   0          2m
```
☝️ Here are your 4 evicted pods!

---

### 2. See Detailed Events for Each Pod

```bash
# Show individual eviction events (not aggregated)
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o custom-columns='TIME:.lastTimestamp,NAMESPACE:.involvedObject.namespace,POD_NAME:.involvedObject.name,MESSAGE:.message'
```

**Output example:**
```
TIME                  NAMESPACE   POD_NAME                          MESSAGE
2025-10-17T02:06:19Z  default     eviction-test-multi-abc123-xyz    The node was low on resource: ephemeral-storage
2025-10-17T02:06:19Z  default     eviction-test-multi-def456-uvw    The node was low on resource: ephemeral-storage
2025-10-17T02:06:19Z  default     eviction-test-multi-ghi789-rst    The node was low on resource: ephemeral-storage
2025-10-17T02:06:19Z  default     eviction-test-multi-jkl012-opq    The node was low on resource: ephemeral-storage
```

---

### 3. Use the Helper Script (Easiest!)

```bash
# Run the detailed eviction checker
./check-eviction-details.sh
```

This shows:
- ✅ All evicted pods by name
- ✅ Individual eviction events
- ✅ Event sources (Kubelet vs Karpenter)
- ✅ Node pressure conditions
- ✅ Summary statistics

---

## How to Create Multiple Evictions (For Testing)

### Option A: Deploy Multiple Test Pods

```bash
# Deploy 4 pods that will all be evicted
kubectl apply -f eviction-test-multiple.yaml

# Watch them all get evicted (~10 seconds)
kubectl get pods -l app=eviction-test-multi -w

# Check the results
kubectl get pods -l app=eviction-test-multi
./check-eviction-details.sh

# Clean up
kubectl delete -f eviction-test-multiple.yaml
```

### Option B: One-Liner Quick Test

```bash
# Create 4 pods that will be evicted
kubectl create deployment evict-test --image=busybox --replicas=4 -- /bin/sh -c 'while true; do dd if=/dev/zero of=/tmp/f-$(date +%s) bs=1M count=100; sleep 1; done' && kubectl set resources deployment evict-test --limits=ephemeral-storage=500Mi && sleep 10 && kubectl get pods -l app=evict-test && kubectl delete deployment evict-test
```

---

## Why Karpenter Shows Multiple Evictions

### Scenario 1: Node Consolidation
```
Before:
Node 1: [Pod A] [Pod B]
Node 2: [Pod C] [Pod D]

Karpenter consolidates:
Node 1: [Pod A] [Pod B] [Pod C] [Pod D]
Node 2: (terminated)

Result: Pods C and D evicted from Node 2, then rescheduled to Node 1
→ 2 eviction events
```

### Scenario 2: Node Replacement
```
Old Node: [Pod A] [Pod B] [Pod C] [Pod D]
Karpenter replaces node (for updates/drift)

Result: All 4 pods evicted, then rescheduled to new node
→ 4 eviction events
```

### Scenario 3: Your Test Deployment
```
Deployment with replicas=4:
- Pod 1: evicted
- Pod 2: evicted  
- Pod 3: evicted
- Pod 4: evicted

Result: 4 eviction events
```

---

## Check If Events Are From Same or Different Pods

### Method 1: JSON Query (Most Accurate)

```bash
kubectl get events --all-namespaces -o json | \
  jq -r '.items[] | select(.reason=="Evicted") | 
  "\(.lastTimestamp) | \(.involvedObject.namespace)/\(.involvedObject.name) | Count: \(.count // 1)"'
```

### Method 2: Simple List

```bash
# Show pod names with event count
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o custom-columns='POD:.involvedObject.name,COUNT:.count,TIME:.lastTimestamp'
```

### Method 3: Grep Events

```bash
kubectl get events --all-namespaces -o wide | grep Evicted
```

---

## Understanding Event "Count" Field

When you see:
```
Count: 4
```

This means the **event was recorded 4 times** for that specific pod/reason combination.

But when you see:
```
4 Evicted: Evicted pod
```

This is an **aggregated summary** meaning 4 different pods had eviction events.

---

## Real Example Walkthrough

Let's create and observe multiple evictions:

```bash
# Step 1: Deploy 4 test pods
kubectl apply -f eviction-test-multiple.yaml

# Step 2: Watch them get created
kubectl get pods -l app=eviction-test-multi

# Step 3: Wait for evictions (~10 seconds)
sleep 12

# Step 4: See the evicted pods
kubectl get pods -l app=eviction-test-multi
# Output:
# NAME                                    READY   STATUS    RESTARTS   AGE
# multi-pod-eviction-test-xxx-abc         0/1     Evicted   0          15s
# multi-pod-eviction-test-xxx-def         0/1     Evicted   0          15s
# multi-pod-eviction-test-xxx-ghi         0/1     Evicted   0          15s
# multi-pod-eviction-test-xxx-jkl         0/1     Evicted   0          15s

# Step 5: See individual events
kubectl get events --field-selector reason=Evicted -o custom-columns='POD:.involvedObject.name,MESSAGE:.message'
# Output:
# POD                                     MESSAGE
# multi-pod-eviction-test-xxx-abc         Pod ephemeral local storage usage exceeds...
# multi-pod-eviction-test-xxx-def         Pod ephemeral local storage usage exceeds...
# multi-pod-eviction-test-xxx-ghi         Pod ephemeral local storage usage exceeds...
# multi-pod-eviction-test-xxx-jkl         Pod ephemeral local storage usage exceeds...

# Step 6: Clean up
kubectl delete -f eviction-test-multiple.yaml
```

---

## Karpenter-Specific Commands

### Check Karpenter Events

```bash
# See what Karpenter is doing
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50 | grep -i evict

# Check node consolidation events
kubectl get events --all-namespaces | grep -i consolidat

# See if nodes are being terminated
kubectl get events --all-namespaces --field-selector involvedObject.kind=Node
```

### Check Which Nodes Karpenter Manages

```bash
# List Karpenter nodes
kubectl get nodes -l karpenter.sh/provisioner-name

# See node age (to understand replacement)
kubectl get nodes --sort-by=.metadata.creationTimestamp
```

---

## Common Questions

### Q: Is one pod being evicted 4 times?
**A:** No! It's 4 separate pods being evicted once each.

### Q: Why don't I see 4 separate events?
**A:** Kubernetes aggregates similar events. Use the commands above to see individual pods.

### Q: Are these pods restarting?
**A:** Evicted pods don't automatically restart. If they come back, it's because a Deployment/ReplicaSet is recreating them.

### Q: How can I prevent this?
**A:** Use Pod Disruption Budgets (PDB) or add annotation: `karpenter.sh/do-not-disrupt: "true"`

---

## Files in This Directory

- ✅ `eviction-test-multiple.yaml` - Deploy 4 pods that will be evicted
- ✅ `check-eviction-details.sh` - Script to see individual eviction details
- ✅ `documents/Karpenter_Eviction_Guide.md` - Complete Karpenter guide

---

## Summary

**What "4 Evicted" means:**
- 4 separate pods were evicted
- Could be from Karpenter node consolidation
- Could be from resource pressure
- Could be from your test deployment

**To see individual pods:**
```bash
kubectl get pods --all-namespaces --field-selector=status.phase=Failed
```

**To see detailed events:**
```bash
./check-eviction-details.sh
```

**To test yourself:**
```bash
kubectl apply -f eviction-test-multiple.yaml
sleep 15
kubectl get pods -l app=eviction-test-multi
kubectl delete -f eviction-test-multiple.yaml
```

