# Kubelet Metrics Access Methods

## Overview

This document explains different methods to access kubelet metrics, specifically focusing on retrieving raw metric data like `kubelet_pod_start_duration_seconds`. We'll compare two main approaches and their use cases.

## Method 1: kubectl get --raw (Recommended)

### Command
```bash
kubectl get --raw /api/v1/nodes/{node-name}/proxy/metrics
```

### How It Works
1. **Kubernetes API Proxy**: Uses the Kubernetes API server as a proxy
2. **Authentication**: Automatically uses your `kubectl` credentials (kubeconfig)
3. **Path Translation**: `/api/v1/nodes/{node-name}/proxy/metrics` gets translated to the actual kubelet endpoint
4. **Security**: Goes through the Kubernetes API server, which handles authentication and authorization

### Network Flow
```
Your kubectl → Kubernetes API Server → Kubelet (10250) → Metrics
```

### Advantages
- ✅ **No RBAC Setup Required**: Uses your existing kubectl permissions
- ✅ **Works from Anywhere**: Can run from your local machine, CI/CD, etc.
- ✅ **Automatic Authentication**: Leverages your kubeconfig
- ✅ **Node Name Resolution**: Uses node names instead of requiring IP addresses
- ✅ **API Server Proxy**: Kubernetes API server handles the complexity
- ✅ **Secure**: API server manages authentication and authorization

### Example Usage
```bash
# Get all kubelet metrics
kubectl get --raw /api/v1/nodes/ip-10-0-17-199.ap-northeast-2.compute.internal/proxy/metrics

# Filter for specific metrics
kubectl get --raw /api/v1/nodes/ip-10-0-17-199.ap-northeast-2.compute.internal/proxy/metrics | grep -i "kubelet_pod_start_duration"

# Get metrics from multiple nodes
kubectl get --raw /api/v1/nodes/ip-10-0-3-40.ap-northeast-2.compute.internal/proxy/metrics | grep -i "kubelet_pod_start_duration"
```

### Sample Output
```
# HELP kubelet_pod_start_duration_seconds [ALPHA] Duration in seconds from kubelet seeing a pod for the first time to the pod starting to run
# TYPE kubelet_pod_start_duration_seconds histogram
kubelet_pod_start_duration_seconds_bucket{le="0.5"} 39
kubelet_pod_start_duration_seconds_bucket{le="1"} 39
kubelet_pod_start_duration_seconds_bucket{le="2"} 43
kubelet_pod_start_duration_seconds_bucket{le="3"} 47
kubelet_pod_start_duration_seconds_bucket{le="4"} 53
kubelet_pod_start_duration_seconds_bucket{le="5"} 55
kubelet_pod_start_duration_seconds_bucket{le="6"} 56
kubelet_pod_start_duration_seconds_bucket{le="8"} 57
kubelet_pod_start_duration_seconds_bucket{le="10"} 57
kubelet_pod_start_duration_seconds_bucket{le="20"} 64
kubelet_pod_start_duration_seconds_bucket{le="30"} 71
kubelet_pod_start_duration_seconds_bucket{le="45"} 74
kubelet_pod_start_duration_seconds_bucket{le="60"} 74
kubelet_pod_start_duration_seconds_bucket{le="120"} 74
kubelet_pod_start_duration_seconds_bucket{le="180"} 74
kubelet_pod_start_duration_seconds_bucket{le="240"} 74
kubelet_pod_start_duration_seconds_bucket{le="300"} 74
kubelet_pod_start_duration_seconds_bucket{le="360"} 74
kubelet_pod_start_duration_seconds_bucket{le="480"} 74
kubelet_pod_start_duration_seconds_bucket{le="600"} 74
kubelet_pod_start_duration_seconds_bucket{le="900"} 74
kubelet_pod_start_duration_seconds_bucket{le="1200"} 74
kubelet_pod_start_duration_seconds_bucket{le="1800"} 74
kubelet_pod_start_duration_seconds_bucket{le="2700"} 74
kubelet_pod_start_duration_seconds_bucket{le="3600"} 74
kubelet_pod_start_duration_seconds_bucket{le="+Inf"} 74
kubelet_pod_start_duration_seconds_sum 442.6225922320001
kubelet_pod_start_duration_seconds_count 74
```

## Method 2: Direct Kubelet Access

### Command
```bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
NODE_IP=<INTERNAL_IP_OF_NODE>
curl -ks -H "Authorization: Bearer $TOKEN" "https://${NODE_IP}:10250/metrics"
```

### How It Works
1. **Direct Access**: Bypasses the Kubernetes API server entirely
2. **Service Account Token**: Uses a Kubernetes service account token for authentication
3. **Direct Connection**: Connects directly to the kubelet's HTTPS endpoint (port 10250)
4. **Pod Context**: This method only works when running inside a pod with proper RBAC

### Network Flow
```
Pod → Kubelet (10250) → Metrics
```

### Requirements
- ❌ **Must run from within a pod**
- ❌ **Requires service account with kubelet access permissions**
- ❌ **Need to know internal node IPs**
- ❌ **Requires RBAC configuration**

### RBAC Setup Required
To make direct kubelet access work, you need to create proper RBAC permissions:

```bash
# 1. Create a ClusterRole with kubelet access
kubectl create clusterrole kubelet-reader \
  --verb=get \
  --resource=nodes/metrics

# 2. Create a ClusterRoleBinding
kubectl create clusterrolebinding kubelet-reader-binding \
  --clusterrole=kubelet-reader \
  --serviceaccount=default:default

# 3. Test from within a pod
kubectl run test-metrics --image=curlimages/curl --rm -it --restart=Never -- /bin/sh -c "
TOKEN=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -ks -H \"Authorization: Bearer \$TOKEN\" \"https://10.0.17.199:10250/metrics\" | grep -i 'kubelet_pod_start_duration' | head -5
"
```

### Advantages
- ✅ **Lower Latency**: Direct connection to kubelet
- ✅ **Performance Critical**: When you need the fastest access
- ✅ **Custom Monitoring**: For building monitoring solutions that run in-cluster
- ✅ **Service Account Context**: When you want to use specific service account permissions

### Disadvantages
- ❌ **Complex Setup**: Requires RBAC configuration
- ❌ **Pod Context Only**: Must run from within a pod
- ❌ **IP Management**: Need to manage internal node IPs
- ❌ **Security Considerations**: Direct access to kubelet

## Comparison Table

| Aspect | kubectl get --raw | Direct kubelet access |
|--------|-------------------|----------------------|
| **Authentication** | Your kubeconfig credentials | Service account token |
| **Network Path** | Via API server proxy | Direct to kubelet |
| **Where it works** | From anywhere with kubectl access | Only from within pods |
| **Security** | API server handles auth/authz | Direct kubelet authentication |
| **Performance** | Slightly higher latency (proxy) | Lower latency (direct) |
| **RBAC** | Uses your user permissions | Uses pod's service account permissions |
| **Setup Complexity** | No setup required | Requires RBAC configuration |
| **IP Management** | Uses node names | Requires internal IPs |
| **Use Case** | General purpose, external access | In-cluster monitoring, performance critical |

## Real-World Example: Pod Start Duration Analysis

### Getting Metrics from Multiple Nodes
```bash
# Node 1: ip-10-0-17-199.ap-northeast-2.compute.internal
kubectl get --raw /api/v1/nodes/ip-10-0-17-199.ap-northeast-2.compute.internal/proxy/metrics | grep -i "kubelet_pod_start_duration"

# Node 2: ip-10-0-3-40.ap-northeast-2.compute.internal  
kubectl get --raw /api/v1/nodes/ip-10-0-3-40.ap-northeast-2.compute.internal/proxy/metrics | grep -i "kubelet_pod_start_duration"
```

### Performance Analysis
From the sample data above:

**Node 1 Performance:**
- Total Pod Starts: 74
- Total Duration: 442.62 seconds
- Average Duration: ~5.98 seconds per pod start

**Node 2 Performance:**
- Total Pod Starts: 70
- Total Duration: 353.03 seconds
- Average Duration: ~5.04 seconds per pod start

**Performance Distribution:**
- Fast Starts (≤1 second): 55-57% of pods
- Medium Starts (1-5 seconds): 21-23% of pods
- Slow Starts (5-30 seconds): 27-29% of pods
- Very Slow Starts (>30 seconds): 4-6% of pods

## Best Practices

### For General Use (Recommended)
```bash
# Use kubectl get --raw for most scenarios
kubectl get --raw /api/v1/nodes/{node-name}/proxy/metrics | grep {metric-name}
```

### For In-Cluster Monitoring
```bash
# Set up proper RBAC first, then use direct access
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -ks -H "Authorization: Bearer $TOKEN" "https://${NODE_IP}:10250/metrics"
```

### Security Considerations
1. **kubectl get --raw**: More secure as it goes through API server
2. **Direct access**: Requires careful RBAC configuration
3. **Service accounts**: Use least-privilege principle
4. **Network policies**: Consider implementing network policies for pod-to-kubelet communication

## Troubleshooting

### Common Issues

#### "no" response from kubectl auth can-i
```bash
# Check if you have node access permissions
kubectl auth can-i get nodes

# If no, you need cluster admin permissions or specific node access
```

#### Direct access returns empty results
```bash
# Check service account permissions
kubectl auth can-i get nodes --as=system:serviceaccount:default:default

# If no, set up RBAC as shown above
```

#### Connection refused errors
```bash
# Verify node is running and accessible
kubectl get nodes

# Check if kubelet is running on the node
kubectl get --raw /api/v1/nodes/{node-name}/proxy/healthz
```

## Conclusion

**For most use cases, including monitoring and debugging, `kubectl get --raw` is the recommended approach** because it's:
- Simpler to use
- More secure
- Doesn't require additional setup
- Works from anywhere with kubectl access

**Use direct kubelet access only when:**
- Building in-cluster monitoring solutions
- Performance is critical
- You need to use specific service account permissions
- You're running from within pods

The choice depends on your specific use case, but for general metric collection and analysis, the `kubectl get --raw` method provides the best balance of simplicity, security, and functionality.
