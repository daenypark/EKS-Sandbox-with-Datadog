# Karpenter Pod Eviction Guide

## Understanding Karpenter Evictions

### What You're Seeing

When you see:
```
4 Evicted: Evicted pod
```

This means **4 separate pods** were evicted, not 1 pod evicted 4 times.

### Types of Pod Evictions

| Type | Trigger | Reason | Event Source |
|------|---------|--------|--------------|
| **Resource Pressure** | Kubelet | Node running out of memory/disk/storage | Kubelet |
| **Karpenter Consolidation** | Karpenter | Node underutilized, pods moved to smaller/fewer nodes | Karpenter |
| **Karpenter Disruption** | Karpenter | Node needs update, replacement, or termination | Karpenter |
| **Pod Preemption** | Scheduler | Higher priority pod needs resources | Scheduler |

---

## Karpenter-Specific Evictions

Karpenter evicts pods in these scenarios:

### 1. Node Consolidation (Most Common)
- **Trigger**: Nodes are underutilized
- **Action**: Karpenter moves pods to fewer/smaller nodes
- **Result**: Multiple pods evicted simultaneously
- **Example**: 4 pods on 2 nodes → consolidated to 1 node → 4 eviction events

### 2. Node Expiry
- **Trigger**: Node reaches TTL (time-to-live)
- **Action**: Karpenter cordons, drains, and replaces node
- **Result**: All pods on that node are evicted

### 3. Node Drift
- **Trigger**: Node configuration drifts from provisioner spec
- **Action**: Karpenter replaces the node
- **Result**: All pods on that node are evicted

### 4. Manual Disruption
- **Trigger**: Provisioner changes or manual intervention
- **Action**: Karpenter replaces nodes
- **Result**: Multiple pods evicted

---

## How to See Individual Pod Evictions

### Check All Recent Eviction Events

```bash
# See all eviction events with pod names
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  --sort-by='.lastTimestamp' \
  -o custom-columns=\
TIME:.lastTimestamp,\
NAMESPACE:.involvedObject.namespace,\
POD:.involvedObject.name,\
REASON:.reason,\
MESSAGE:.message
```

### Check Karpenter Events

```bash
# See Karpenter-specific events
kubectl get events -n karpenter --sort-by='.lastTimestamp'

# Filter for disruption events
kubectl get events --all-namespaces | grep -i "karpenter\|consolidat\|disrupt"
```

### Check Pod Disruption Details

```bash
# List all failed/evicted pods
kubectl get pods --all-namespaces --field-selector=status.phase=Failed

# Get details of a specific evicted pod
kubectl describe pod <pod-name> -n <namespace>

# Check pod status reason
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.status.reason=="Evicted") | {name: .metadata.name, namespace: .metadata.namespace, reason: .status.reason, message: .status.message}'
```

### Check Karpenter Node Events

```bash
# See node events (cordon, drain, terminate)
kubectl get events --all-namespaces --field-selector involvedObject.kind=Node

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100

# See which nodes Karpenter manages
kubectl get nodes -l karpenter.sh/provisioner-name
```

---

## Triggering Multiple Pod Evictions

### Method 1: Deploy Multiple Pods and Trigger Consolidation

```yaml
# karpenter-eviction-test.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: low-utilization-pods
  namespace: default
spec:
  replicas: 10  # Deploy 10 pods
  selector:
    matchLabels:
      app: low-util
  template:
    metadata:
      labels:
        app: low-util
    spec:
      containers:
      - name: nginx
        image: nginx
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: low-util
```

Deploy and then delete some pods to trigger consolidation:

```bash
# Deploy the pods
kubectl apply -f karpenter-eviction-test.yaml

# Wait for pods to spread across nodes
kubectl get pods -l app=low-util -o wide

# See which nodes are created
kubectl get nodes -l karpenter.sh/provisioner-name

# Now scale down to trigger consolidation
kubectl scale deployment low-utilization-pods --replicas=2

# Watch Karpenter consolidate nodes (pods will be evicted)
kubectl get events --all-namespaces --watch | grep -i "evict\|consolidat"

# Check for eviction events
kubectl get events --all-namespaces --field-selector reason=Evicted
```

### Method 2: Force Node Consolidation with Empty Nodes

```bash
# 1. Deploy pods that spread across multiple nodes
kubectl apply -f karpenter-eviction-test.yaml

# 2. Wait for nodes to be created
sleep 30
kubectl get nodes

# 3. Delete most pods to make nodes underutilized
kubectl scale deployment low-utilization-pods --replicas=1

# 4. Wait for Karpenter to detect and consolidate (default: 30s)
# Karpenter will evict the remaining pod and consolidate nodes
sleep 60

# 5. Check events - you should see eviction events
kubectl get events --all-namespaces --field-selector reason=Evicted
```

### Method 3: Trigger Node Expiry

Check your Karpenter provisioner TTL settings:

```bash
# Check provisioner configuration
kubectl get provisioner -o yaml

# Look for ttlSecondsAfterEmpty and ttlSecondsUntilExpired
```

Example provisioner with short TTL (for testing):

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: test-eviction
spec:
  ttlSecondsAfterEmpty: 30    # Terminate empty nodes after 30s
  ttlSecondsUntilExpired: 300 # Expire nodes after 5 minutes
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["on-demand"]
  limits:
    resources:
      cpu: "10"
      memory: "20Gi"
  providerRef:
    name: default
```

### Method 4: Multiple Resource-Pressure Evictions

Deploy multiple pods that will hit resource limits:

```yaml
# multiple-eviction-test.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-eviction-test
spec:
  replicas: 5  # Create 5 pods that will all be evicted
  selector:
    matchLabels:
      app: eviction-multi
  template:
    metadata:
      labels:
        app: eviction-multi
    spec:
      containers:
      - name: storage-filler
        image: busybox
        command:
        - /bin/sh
        - -c
        - |
          while true; do
            dd if=/dev/zero of=/tmp/fill-$(date +%s) bs=1M count=100
            sleep 1
          done
        resources:
          limits:
            ephemeral-storage: "500Mi"
          requests:
            ephemeral-storage: "200Mi"
      restartPolicy: Always
```

Deploy:

```bash
kubectl apply -f multiple-eviction-test.yaml

# Watch multiple pods get evicted
kubectl get pods -l app=eviction-multi -w

# Check events - you should see multiple eviction events
kubectl get events --field-selector reason=Evicted --sort-by='.lastTimestamp'
```

---

## Understanding the Event Aggregation

Kubernetes aggregates similar events. What you're seeing:

```
4 Evicted: Evicted pod
Count: 4
```

This means the **same type of event happened 4 times** (4 different pods evicted).

### View Individual Events

```bash
# Get detailed, non-aggregated events
kubectl get events --all-namespaces -o json | \
  jq '.items[] | select(.reason=="Evicted") | {
    time: .lastTimestamp,
    pod: .involvedObject.name,
    namespace: .involvedObject.namespace,
    message: .message,
    count: .count
  }'
```

### View Events with Pod Names

```bash
# Show each evicted pod clearly
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o custom-columns=\
'TIME:.lastTimestamp,NAMESPACE:.involvedObject.namespace,POD:.involvedObject.name,COUNT:.count,MESSAGE:.message'
```

---

## Monitoring Karpenter Evictions

### Check Karpenter Metrics

If you have Prometheus/Datadog:

```bash
# Karpenter metrics to watch
karpenter_nodes_terminated
karpenter_pods_evicted
karpenter_consolidation_actions
karpenter_interruption_actions
```

### Check Karpenter Controller Logs

```bash
# View recent Karpenter decisions
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50 | grep -i "evict\|consolidat\|disrupt"

# Follow live logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

### Check Node Status

```bash
# See if nodes are being cordoned/drained
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status,SCHEDULABLE:.spec.unschedulable,AGE:.metadata.creationTimestamp'

# Check node conditions for pressure
kubectl describe nodes | grep -A 5 "Conditions:"
```

---

## Preventing Unwanted Karpenter Evictions

### 1. Use Pod Disruption Budgets (PDB)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2  # Keep at least 2 pods available
  selector:
    matchLabels:
      app: my-app
```

### 2. Use Do-Not-Disrupt Annotation

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: critical-pod
  annotations:
    karpenter.sh/do-not-disrupt: "true"  # Prevent Karpenter from evicting
spec:
  containers:
  - name: app
    image: nginx
```

### 3. Configure Consolidation Settings

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  consolidation:
    enabled: true
  ttlSecondsAfterEmpty: 30
  ttlSecondsUntilExpired: 604800  # 7 days
```

---

## Example: Complete Test Scenario

Here's a complete example to see multiple evictions:

```bash
# 1. Deploy multiple test pods
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: eviction-test-multi
spec:
  replicas: 4
  selector:
    matchLabels:
      app: eviction-test
  template:
    metadata:
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
          while true; do
            dd if=/dev/zero of=/tmp/fill-\$(date +%s) bs=1M count=100
            sleep 1
          done
        resources:
          limits:
            ephemeral-storage: "500Mi"
EOF

# 2. Watch all 4 pods get evicted (takes ~10 seconds)
kubectl get pods -l app=eviction-test -w

# 3. Check events - you should see 4 separate eviction events
kubectl get events --field-selector reason=Evicted --sort-by='.lastTimestamp'

# 4. View detailed breakdown
kubectl get events --field-selector reason=Evicted -o json | \
  jq -r '.items[] | "\(.involvedObject.name) - \(.message)"'

# 5. Clean up
kubectl delete deployment eviction-test-multi
```

---

## Debugging Multiple Evictions

### Question: Why do I see "4 Evicted" instead of individual pod names?

**Answer**: Kubernetes event aggregation. Events of the same type are grouped together.

To see individual pods:

```bash
# Method 1: Use JSON output
kubectl get events --all-namespaces -o json | \
  jq '.items[] | select(.reason=="Evicted") | "\(.involvedObject.namespace)/\(.involvedObject.name): \(.message)"'

# Method 2: Use wide output
kubectl get events --all-namespaces -o wide | grep Evicted

# Method 3: Check pod status directly
kubectl get pods --all-namespaces --field-selector=status.phase=Failed
```

### Question: Are these from one pod restarting 4 times?

**Answer**: No. Evicted pods don't restart on their own (unless part of a Deployment/ReplicaSet). These are 4 separate pod eviction events.

To verify:

```bash
# Check if pods have restart counts
kubectl get pods --all-namespaces -o custom-columns=\
'NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,STATUS:.status.phase,REASON:.status.reason'

# Evicted pods show:
# - RESTARTS: 0 (or whatever it was before eviction)
# - STATUS: Failed
# - REASON: Evicted
```

### Question: How do I differentiate Karpenter evictions from kubelet evictions?

**Answer**: Check the event source and message:

```bash
# View event sources
kubectl get events --all-namespaces -o custom-columns=\
'TIME:.lastTimestamp,SOURCE:.source.component,POD:.involvedObject.name,REASON:.reason,MESSAGE:.message' | \
grep Evicted
```

- **Kubelet evictions**: Source = `kubelet`, Message mentions resource pressure
- **Karpenter evictions**: Source = `karpenter`, Message mentions consolidation/disruption

---

## Summary

**What you're seeing:**
- ✅ **4 separate pods** were evicted (not 1 pod evicted 4 times)
- ✅ Events are **aggregated** by Kubernetes
- ✅ **Karpenter** was likely consolidating nodes

**Common scenarios:**
1. **Karpenter consolidation**: 4 pods moved to fewer nodes
2. **Resource pressure**: 4 pods hit limits simultaneously
3. **Node drain**: All pods on a node being terminated
4. **Multiple test pods**: Your test deployment had multiple replicas

**To investigate:**
```bash
# See individual evicted pods
kubectl get pods --all-namespaces --field-selector=status.phase=Failed

# See detailed events
kubectl get events --all-namespaces -o json | jq '.items[] | select(.reason=="Evicted")'

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100
```





