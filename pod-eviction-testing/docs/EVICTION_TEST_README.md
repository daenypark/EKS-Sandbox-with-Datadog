# Quick Start - Pod Eviction Testing

## Fastest Method (Recommended) 🚀

Run the automated script:

```bash
cd /Users/danny.park/ekstest/config_files
./eviction-quick-test.sh
```

This will automatically deploy a pod, monitor it, show the eviction event, and clean up.

---

## Manual Testing Methods

### Method 1: Ephemeral Storage Eviction (5-10 seconds)

```bash
# Deploy
kubectl apply -f eviction-test-ephemeral.yaml

# Watch (it will show "Evicted" status)
kubectl get pods eviction-test-ephemeral -w

# Check events
kubectl get events --field-selector involvedObject.name=eviction-test-ephemeral

# Clean up
kubectl delete pod eviction-test-ephemeral
```

### Method 2: Memory Pressure Eviction (immediate OOMKilled)

```bash
# Deploy
kubectl apply -f eviction-test-memory.yaml

# Watch
kubectl get pods eviction-test-memory -w

# Check events
kubectl describe pod eviction-test-memory

# Clean up
kubectl delete pod eviction-test-memory
```

### Method 3: Pod Priority/Preemption

```bash
# Apply priority classes and low-priority pods
kubectl apply -f eviction-test-priority.yaml

# Wait for low-priority pods to be running
kubectl get pods -l app=low-priority-app

# The high-priority pod will preempt low-priority ones if resources are tight
kubectl get events | grep -i preempt

# Clean up
kubectl delete -f eviction-test-priority.yaml
```

---

## Monitoring Eviction Events

### Real-time Event Watching

```bash
# Watch all events
kubectl get events --all-namespaces --watch

# Show only eviction events
kubectl get events --all-namespaces --field-selector reason=Evicted

# Pretty format
kubectl get events --all-namespaces --sort-by='.lastTimestamp' -o custom-columns=TIME:.lastTimestamp,NAMESPACE:.involvedObject.namespace,POD:.involvedObject.name,REASON:.reason,MESSAGE:.message | grep Evicted
```

### Check for Evicted Pods

```bash
# List all evicted/failed pods
kubectl get pods --all-namespaces --field-selector=status.phase=Failed

# Get details
kubectl describe pod <pod-name>
```

### Node Resource Status

```bash
# Check node conditions (MemoryPressure, DiskPressure, etc.)
kubectl describe nodes | grep -E "MemoryPressure|DiskPressure|PIDPressure"

# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces
```

---

## One-Liner for Quick Test

```bash
kubectl run eviction-test --image=busybox --restart=Never --overrides='{"spec":{"containers":[{"name":"test","image":"busybox","command":["/bin/sh","-c","while true; do dd if=/dev/zero of=/tmp/fill-$(date +%s) bs=1M count=100; sleep 1; done"],"resources":{"limits":{"ephemeral-storage":"500Mi"}}}]}}' && sleep 5 && kubectl get pods eviction-test -w
```

---

## Expected Output

When a pod is evicted, you'll see:

### kubectl get pods
```
NAME                       READY   STATUS    RESTARTS   AGE
eviction-test-ephemeral    0/1     Evicted   0          8s
```

### kubectl describe pod
```
Status:       Failed
Reason:       Evicted
Message:      The node was low on resource: ephemeral-storage. Container storage-filler was using 512Mi, which exceeds its request of 200Mi.
```

### kubectl get events
```
LAST SEEN   TYPE      REASON    OBJECT                          MESSAGE
8s          Warning   Evicted   pod/eviction-test-ephemeral     The node was low on resource: ephemeral-storage
```

---

## Files in This Directory

- `eviction-quick-test.sh` - Automated test script (recommended)
- `eviction-test-ephemeral.yaml` - Ephemeral storage test (fastest)
- `eviction-test-memory.yaml` - Memory pressure test
- `eviction-test-priority.yaml` - Priority/preemption test
- `documents/Pod_Eviction_Testing_Guide.md` - Complete documentation

---

## Troubleshooting

**Pod not getting evicted?**
- Wait longer (up to 30 seconds for some methods)
- Check if the pod is even scheduled: `kubectl describe pod <pod-name>`
- Ensure node has resources to schedule initially
- Try the memory method for immediate eviction

**Events disappeared?**
- Kubernetes events expire after 1 hour
- Use `kubectl describe pod` to see persistent history

**Need to test in production?**
- Start with namespace isolation
- Test during low-traffic periods
- Have monitoring/alerting ready
- Always clean up test resources

---

## Clean Up All Test Resources

```bash
# Delete all test pods and deployments
kubectl delete pod eviction-test-ephemeral --ignore-not-found
kubectl delete pod eviction-test-memory --ignore-not-found
kubectl delete pod quick-eviction-test --ignore-not-found
kubectl delete -f eviction-test-priority.yaml --ignore-not-found

# Check for any remaining evicted pods
kubectl get pods --all-namespaces --field-selector=status.phase=Failed
```

---

## Next Steps

1. **Run the quick test**: `./eviction-quick-test.sh`
2. **Monitor in Datadog**: Check for pod eviction events
3. **Set up alerts**: Configure alerts for pod evictions
4. **Test runbooks**: Verify your incident response procedures

For detailed explanations and additional methods, see:
`documents/Pod_Eviction_Testing_Guide.md`

