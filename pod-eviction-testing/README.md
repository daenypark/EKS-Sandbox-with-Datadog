# Pod Eviction Testing Suite

Complete toolkit for testing, monitoring, and understanding Kubernetes pod eviction events in EKS.

## 📁 Directory Structure

```
pod-eviction-testing/
├── README.md                          # This file
├── scripts/                           # Executable scripts
│   ├── eviction-quick-test.sh        # Automated eviction test (recommended)
│   ├── check-eviction-details.sh     # View detailed eviction events
│   ├── show-aggregated-events.sh     # View aggregated event format
│   └── verify-event-source.sh        # Verify K8s vs monitoring tool aggregation
├── yaml-configs/                      # Kubernetes manifests
│   ├── eviction-test-ephemeral.yaml  # Ephemeral storage test (fastest)
│   ├── eviction-test-memory.yaml     # Memory pressure test
│   ├── eviction-test-multiple.yaml   # Multiple pod eviction test
│   └── eviction-test-priority.yaml   # Priority/preemption test
└── docs/                              # Documentation
    ├── EVICTION_TEST_README.md       # Quick start guide
    ├── Pod_Eviction_Testing_Guide.md # Complete testing guide
    ├── Karpenter_Eviction_Guide.md   # Karpenter-specific evictions
    ├── MULTIPLE_EVICTION_HOWTO.md    # Understanding multiple evictions
    └── EVENT_AGGREGATION_EXPLAINED.md # K8s event aggregation explained
```

---

## 🚀 Quick Start

### Option 1: Automated Script (Easiest)
```bash
cd pod-eviction-testing
./scripts/eviction-quick-test.sh
```

### Option 2: Manual YAML Deployment
```bash
cd pod-eviction-testing
kubectl apply -f yaml-configs/eviction-test-ephemeral.yaml
kubectl get pods eviction-test-ephemeral -w
```

### Option 3: Deploy Multiple Pods for Testing
```bash
cd pod-eviction-testing
kubectl apply -f yaml-configs/eviction-test-multiple.yaml
sleep 12
./scripts/check-eviction-details.sh
kubectl delete -f yaml-configs/eviction-test-multiple.yaml
```

---

## 📖 Documentation Guide

### For Quick Testing
→ Start here: **`docs/EVICTION_TEST_README.md`**

### For Understanding Multiple Evictions
→ Read: **`docs/MULTIPLE_EVICTION_HOWTO.md`**

### For Event Aggregation Questions
→ Read: **`docs/EVENT_AGGREGATION_EXPLAINED.md`**

### For Comprehensive Testing
→ Read: **`docs/Pod_Eviction_Testing_Guide.md`**

### For Karpenter-Specific Issues
→ Read: **`docs/Karpenter_Eviction_Guide.md`**

---

## 🛠️ Script Usage

### 1. eviction-quick-test.sh
Automated test that deploys a pod, monitors eviction, and cleans up.

```bash
./scripts/eviction-quick-test.sh
```

**Output:** Complete eviction lifecycle with colored output

---

### 2. check-eviction-details.sh
Shows detailed information about evicted pods (de-aggregated view).

```bash
./scripts/check-eviction-details.sh
```

**Shows:**
- All evicted pods by name
- Individual eviction events
- Event sources (Kubelet vs Karpenter)
- Node pressure conditions

---

### 3. show-aggregated-events.sh
Shows events in aggregated format (like monitoring tools).

```bash
./scripts/show-aggregated-events.sh
```

**Shows:**
- Event aggregation by count
- Summary statistics
- How events are merged

---

### 4. verify-event-source.sh
Verifies whether event aggregation is from Kubernetes or monitoring tools.

```bash
./scripts/verify-event-source.sh
```

**Shows:**
- Raw Kubernetes event count
- Whether K8s merged events
- Source of aggregation (K8s vs monitoring tool)

---

## 📋 YAML Configuration Files

### eviction-test-ephemeral.yaml
**Purpose:** Fastest eviction test (5-10 seconds)
**Method:** Fills ephemeral storage beyond limit
**Use case:** Quick testing, safe for any environment

```bash
kubectl apply -f yaml-configs/eviction-test-ephemeral.yaml
```

---

### eviction-test-memory.yaml
**Purpose:** Immediate eviction via memory pressure
**Method:** Consumes more memory than limit
**Use case:** Testing OOMKilled scenarios

```bash
kubectl apply -f yaml-configs/eviction-test-memory.yaml
```

---

### eviction-test-multiple.yaml
**Purpose:** Test multiple pod evictions simultaneously
**Method:** Deploys 4 pods that all exceed storage limits
**Use case:** Understanding event aggregation

```bash
kubectl apply -f yaml-configs/eviction-test-multiple.yaml
```

---

### eviction-test-priority.yaml
**Purpose:** Test pod priority and preemption
**Method:** High-priority pods evict low-priority ones
**Use case:** Testing priority classes and preemption

```bash
kubectl apply -f yaml-configs/eviction-test-priority.yaml
```

---

## 🔍 Common Commands

### Check for Evicted Pods
```bash
kubectl get pods --all-namespaces --field-selector=status.phase=Failed
```

### Watch for Eviction Events
```bash
kubectl get events --all-namespaces --field-selector reason=Evicted -w
```

### Check Node Pressure
```bash
kubectl describe nodes | grep -E "MemoryPressure|DiskPressure|PIDPressure"
```

### View Karpenter Events
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50
```

---

## 🧹 Cleanup

### Clean Up All Test Resources
```bash
cd pod-eviction-testing

# Delete individual test pods
kubectl delete -f yaml-configs/eviction-test-ephemeral.yaml --ignore-not-found
kubectl delete -f yaml-configs/eviction-test-memory.yaml --ignore-not-found
kubectl delete -f yaml-configs/eviction-test-multiple.yaml --ignore-not-found
kubectl delete -f yaml-configs/eviction-test-priority.yaml --ignore-not-found

# Or delete all at once
kubectl delete -f yaml-configs/ --ignore-not-found

# Check for any remaining evicted pods
kubectl get pods --all-namespaces --field-selector=status.phase=Failed
```

---

## ❓ FAQ

### Q: Which test should I run first?
**A:** Run `./scripts/eviction-quick-test.sh` - it's automated and shows the complete flow.

### Q: How do I see individual pod names when multiple pods are evicted?
**A:** Run `./scripts/check-eviction-details.sh`

### Q: Why do I see "4 Evicted" instead of 4 separate events?
**A:** Read `docs/EVENT_AGGREGATION_EXPLAINED.md` - it's monitoring tool aggregation, not K8s.

### Q: How can I test Karpenter evictions?
**A:** See `docs/Karpenter_Eviction_Guide.md` for Karpenter-specific scenarios.

### Q: Are these tests safe for production?
**A:** The ephemeral storage test is safest. Always test in dev/staging first.

---

## 🎯 Key Concepts

### Event Aggregation
- **Kubernetes merges:** Events for the SAME pod with SAME reason (increases COUNT)
- **Kubernetes does NOT merge:** Events for DIFFERENT pods
- **Monitoring tools merge:** Similar events for display purposes

### Pod Eviction Triggers
1. **Resource Pressure:** Node runs out of memory/disk/storage
2. **Karpenter Consolidation:** Pods moved to fewer nodes
3. **Pod Preemption:** Higher priority pods evict lower priority
4. **Node Maintenance:** Node drain/cordon operations

### QoS Classes (Eviction Order)
1. **BestEffort** (evicted first) - No requests/limits
2. **Burstable** (evicted second) - Requests < Limits
3. **Guaranteed** (evicted last) - Requests = Limits

---

## 📞 Support

For issues or questions:
1. Check the documentation in `docs/`
2. Run `./scripts/check-eviction-details.sh` for diagnostics
3. Review Kubernetes events: `kubectl get events --sort-by='.lastTimestamp'`

---

## 📝 Examples

### Example 1: Quick Single Pod Eviction Test
```bash
cd pod-eviction-testing
./scripts/eviction-quick-test.sh
```

### Example 2: Test Multiple Pod Evictions
```bash
cd pod-eviction-testing
kubectl apply -f yaml-configs/eviction-test-multiple.yaml
kubectl get pods -l app=eviction-test-multi -w
./scripts/check-eviction-details.sh
kubectl delete -f yaml-configs/eviction-test-multiple.yaml
```

### Example 3: Check Event Aggregation
```bash
cd pod-eviction-testing
./scripts/verify-event-source.sh
```

---

## 🔗 Related Resources

- [Kubernetes Pod Priority and Preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)
- [Node Pressure Eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)
- [Karpenter Documentation](https://karpenter.sh/)

---

**Created:** October 17, 2025
**Purpose:** EKS pod eviction testing and monitoring
**Maintainer:** Danny Park





