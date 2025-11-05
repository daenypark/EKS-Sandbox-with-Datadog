# Pod Eviction Testing Guide

## Overview

This guide provides multiple methods to manually trigger pod eviction events in your EKS cluster for testing purposes (monitoring, alerting, cluster behavior, etc.).

## Table of Contents

1. [Understanding Pod Eviction](#understanding-pod-eviction)
2. [Method 1: Ephemeral Storage Pressure (Easiest)](#method-1-ephemeral-storage-pressure-easiest)
3. [Method 2: Memory Pressure](#method-2-memory-pressure)
4. [Method 3: Node Disk Pressure](#method-3-node-disk-pressure)
5. [Method 4: Low Resource Limits](#method-4-low-resource-limits)
6. [Method 5: Pod Priority and Preemption](#method-5-pod-priority-and-preemption)
7. [Verification and Monitoring](#verification-and-monitoring)

---

## Understanding Pod Eviction

Pod eviction occurs when:
- **Node Resource Pressure**: Node runs out of memory, disk, or ephemeral storage
- **Kubelet Eviction Thresholds**: Default thresholds trigger eviction
- **Pod Priority/Preemption**: Higher priority pods evict lower priority ones
- **Quality of Service (QoS)**: BestEffort pods are evicted first, then Burstable, then Guaranteed

### Default Kubelet Eviction Thresholds
```
memory.available < 100Mi
nodefs.available < 10%
nodefs.inodesFree < 5%
imagefs.available < 15%
```

---

## Method 1: Ephemeral Storage Pressure (Easiest)

This is the **quickest and safest** method. The pod writes data to ephemeral storage exceeding its limit.

### Create Test Pod: `eviction-test-ephemeral.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: eviction-test-ephemeral
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
        dd if=/dev/zero of=/tmp/fill-$(date +%s) bs=1M count=100
        sleep 1
      done
    resources:
      limits:
        ephemeral-storage: "500Mi"
      requests:
        ephemeral-storage: "200Mi"
  restartPolicy: Never
```

### Deploy and Monitor

```bash
# Deploy the pod
kubectl apply -f eviction-test-ephemeral.yaml

# Watch the pod (it will be evicted after ~5-10 seconds)
kubectl get pods eviction-test-ephemeral -w

# Check events (you'll see "Evicted" reason)
kubectl get events --field-selector involvedObject.name=eviction-test-ephemeral --sort-by='.lastTimestamp'

# Describe the pod to see eviction details
kubectl describe pod eviction-test-ephemeral
```

### Expected Output
```
NAME                       READY   STATUS    RESTARTS   AGE
eviction-test-ephemeral    1/1     Running   0          3s
eviction-test-ephemeral    0/1     Evicted   0          8s
```

---

## Method 2: Memory Pressure

Force the pod to consume more memory than its limit, causing immediate eviction.

### Create Test Pod: `eviction-test-memory.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: eviction-test-memory
  labels:
    app: eviction-test
spec:
  containers:
  - name: memory-consumer
    image: polinux/stress
    command:
    - stress
    - --vm
    - "1"
    - --vm-bytes
    - "250M"
    - --vm-hang
    - "1"
    resources:
      limits:
        memory: "200Mi"
      requests:
        memory: "100Mi"
  restartPolicy: Never
```

### Deploy and Monitor

```bash
# Deploy the pod
kubectl apply -f eviction-test-memory.yaml

# Watch the pod (will be OOMKilled or Evicted)
kubectl get pods eviction-test-memory -w

# Check events
kubectl describe pod eviction-test-memory | grep -A 10 Events
```

---

## Method 3: Node Disk Pressure

Fill up the node's disk to trigger node-level eviction. **Warning: This affects the entire node.**

### Create Test Pod: `eviction-test-disk-pressure.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: disk-pressure-pods
spec:
  replicas: 3
  selector:
    matchLabels:
      app: disk-pressure
  template:
    metadata:
      labels:
        app: disk-pressure
    spec:
      containers:
      - name: disk-filler
        image: busybox
        command:
        - /bin/sh
        - -c
        - |
          # Fill disk slowly to avoid immediate crash
          for i in $(seq 1 100); do
            dd if=/dev/zero of=/tmp/bigfile-$i bs=1M count=500
            sleep 2
          done
          sleep 3600
        volumeMounts:
        - name: data
          mountPath: /tmp
      volumes:
      - name: data
        emptyDir: {}
```

### Deploy and Monitor

```bash
# Deploy the pods
kubectl apply -f eviction-test-disk-pressure.yaml

# Watch node conditions
kubectl describe nodes | grep -A 5 "Conditions:"

# Watch for evictions
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep Evicted

# Clean up when done
kubectl delete deployment disk-pressure-pods
```

---

## Method 4: Low Resource Limits

Create pods with very low limits that will be evicted when resources are needed.

### Create Test Pod: `eviction-test-low-limits.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: eviction-test-low-limits
  labels:
    app: eviction-test
spec:
  containers:
  - name: app
    image: nginx
    resources:
      limits:
        memory: "50Mi"
        cpu: "50m"
      requests:
        memory: "10Mi"
        cpu: "10m"
```

Then create a high-priority pod to trigger eviction:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: high-priority-pod
spec:
  priorityClassName: system-cluster-critical  # Built-in high priority
  containers:
  - name: app
    image: nginx
    resources:
      requests:
        memory: "1Gi"
        cpu: "500m"
```

---

## Method 5: Pod Priority and Preemption

Use pod priority to force eviction of lower-priority pods.

### Step 1: Create Priority Classes

```yaml
# low-priority.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: 100
globalDefault: false
description: "Low priority class for testing eviction"
---
# high-priority.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 10000
preemptionPolicy: PreemptLowerPriority
globalDefault: false
description: "High priority class that can preempt low priority pods"
```

### Step 2: Deploy Low Priority Pods

```yaml
# eviction-test-priority.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: low-priority-deployment
spec:
  replicas: 5
  selector:
    matchLabels:
      app: low-priority-app
  template:
    metadata:
      labels:
        app: low-priority-app
    spec:
      priorityClassName: low-priority
      containers:
      - name: app
        image: nginx
        resources:
          requests:
            memory: "500Mi"
            cpu: "500m"
```

### Step 3: Deploy High Priority Pod to Trigger Eviction

```yaml
# high-priority-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: high-priority-pod-test
spec:
  priorityClassName: high-priority
  containers:
  - name: app
    image: nginx
    resources:
      requests:
        memory: "2Gi"
        cpu: "1000m"
```

### Execute the Test

```bash
# Create priority classes
kubectl apply -f low-priority.yaml
kubectl apply -f high-priority.yaml

# Deploy low-priority pods first
kubectl apply -f eviction-test-priority.yaml

# Wait for them to be running
kubectl get pods -l app=low-priority-app

# Deploy high-priority pod (this will cause eviction if resources are tight)
kubectl apply -f high-priority-pod.yaml

# Watch for evictions
kubectl get events --sort-by='.lastTimestamp' | grep -i preempt
kubectl get pods -A -w
```

---

## Verification and Monitoring

### Check for Evicted Pods

```bash
# List all evicted pods
kubectl get pods --all-namespaces --field-selector=status.phase=Failed

# Get detailed eviction events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep Evicted

# Check specific pod status
kubectl describe pod <pod-name>
```

### Check Node Conditions

```bash
# View node pressure conditions
kubectl describe nodes | grep -E "MemoryPressure|DiskPressure|PIDPressure"

# Get node resource usage
kubectl top nodes

# Get pod resource usage
kubectl top pods --all-namespaces
```

### Monitor with kubectl events

```bash
# Watch events in real-time
kubectl get events --all-namespaces --watch

# Filter for eviction events
kubectl get events --all-namespaces --field-selector reason=Evicted

# Pretty print events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' -o custom-columns=TIME:.lastTimestamp,NAMESPACE:.involvedObject.namespace,POD:.involvedObject.name,REASON:.reason,MESSAGE:.message
```

### Check Datadog Monitoring (if configured)

```bash
# Events should show up in Datadog with tags:
# - pod_name
# - reason:Evicted
# - namespace
# - cluster_name
```

---

## Quick Start - Easiest Method

Use this for immediate testing:

```bash
# 1. Create the ephemeral storage eviction test
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: quick-eviction-test
spec:
  containers:
  - name: storage-filler
    image: busybox
    command: ["/bin/sh", "-c", "while true; do dd if=/dev/zero of=/tmp/fill-\$(date +%s) bs=1M count=100; sleep 1; done"]
    resources:
      limits:
        ephemeral-storage: "500Mi"
  restartPolicy: Never
EOF

# 2. Watch it get evicted (takes ~5-10 seconds)
kubectl get pods quick-eviction-test -w

# 3. Check the eviction event
kubectl get events --field-selector involvedObject.name=quick-eviction-test

# 4. Clean up
kubectl delete pod quick-eviction-test
```

---

## Cleanup

After testing, clean up all test resources:

```bash
# Delete all eviction test pods
kubectl delete pod eviction-test-ephemeral --ignore-not-found
kubectl delete pod eviction-test-memory --ignore-not-found
kubectl delete pod eviction-test-low-limits --ignore-not-found
kubectl delete pod high-priority-pod --ignore-not-found
kubectl delete pod quick-eviction-test --ignore-not-found

# Delete deployments
kubectl delete deployment disk-pressure-pods --ignore-not-found
kubectl delete deployment low-priority-deployment --ignore-not-found

# Delete priority classes (optional)
kubectl delete priorityclass low-priority --ignore-not-found
kubectl delete priorityclass high-priority --ignore-not-found

# Check for any remaining evicted pods
kubectl get pods --all-namespaces --field-selector=status.phase=Failed
```

---

## Troubleshooting

### Pod Not Getting Evicted

1. **Increase resource consumption**: Make the pod consume more resources faster
2. **Lower resource limits**: Reduce limits in the pod spec
3. **Check node capacity**: Ensure node has enough resources to schedule the pod initially
4. **Check QoS class**: Use BestEffort QoS (no requests/limits) for easier eviction

### Cannot See Eviction Events

```bash
# Events expire after 1 hour by default, check immediately after eviction
kubectl get events --sort-by='.lastTimestamp' | head -20

# Use describe for persistent event history on the pod
kubectl describe pod <pod-name>
```

---

## Summary

**Recommended Method for Testing**: Method 1 (Ephemeral Storage Pressure)
- ✅ Fast (5-10 seconds)
- ✅ Safe (doesn't affect other pods)
- ✅ Easy to reproduce
- ✅ Clean eviction event

**Production Monitoring**: Set up alerts for:
- Pod eviction events
- Node pressure conditions (Memory, Disk, PID)
- Pod restart counts
- QoS class monitoring

