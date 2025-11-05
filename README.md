# Datadog Infrastructure Overview - EKS Cluster

This document describes the overall Datadog monitoring infrastructure across EC2 and Fargate workloads in the EKS cluster.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          EKS Cluster: danny-eks-cluster                         │
│                                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                         Datadog Operator (agent-operator.yaml)             │ │
│  │  • Manages DaemonSet agents on EC2 nodes                                   │ │
│  │  • Handles Fargate sidecar injection                                       │ │
│  │  • Provides Single Step Instrumentation (SSI) for Java apps                │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│  ┌──────────────────────────────────┐  ┌──────────────────────────────────────┐ │
│  │        EC2 Node Workloads        │  │        Fargate Workloads             │ │
│  │         (default namespace)      │  │         (fargate namespace)          │ │
│  │                                  │  │                                      │ │
│  │  ┌────────────────────────────┐  │  │  ┌────────────────────────────────┐  │ │
│  │  │  test-java-app             │  │  │  │  dogstatsd-python-app          │  │ │
│  │  │  (spring-boot-demo)        │  │  │  │  (mydogstatsdpod)              │  │ │
│  │  │                            │  │  │  │                                │  │ │
│  │  │  Features:                 │  │  │  │  Features:                     │  │ │
│  │  │  ✅ SSI (Auto-injection)   │  │  │  │  ✅ Custom Instrumentation      │  │ │
│  │  │  ✅ APM via UDS            │  │  │  │  ✅ DogStatsD custom metrics    │  │ │
│  │  │  ✅ DaemonSet agent        │  │  │  │  ✅ Sidecar injection           │  │ │
│  │  │  ❌ No sidecar             │  │  │  │  ❌ No SSI                      │  │ │
│  │  │                            │  │  │  │                                │  │ │
│  │  │  Image: spring-boot-demo:  │  │  │  │  Image: fargate-py:latest      │  │ │
│  │  │         latest             │  │  │  │  Service: dogstatsd-python-app │  │ │
│  │  │  Replicas: 2               │  │  │  │  Type: Pod                     │  │ │
│  │  └────────────────────────────┘  │  │  └────────────────────────────────┘  │ │
│  │            │                     │  │            │                         │ │
│  │            │ Unix Socket         │  │            │ localhost:8126          │ │
│  │            ▼                     │  │            ▼                         │ │
│  │  ┌────────────────────────────┐  │  │  ┌────────────────────────────────┐  │ │
│  │  │  Datadog Agent DaemonSet   │  │  │  │  spring-boot-demo-fargate      │  │ │
│  │  │  (Runs on EC2 node)        │  │  │  │                                │  │ │
│  │  │                            │  │  │  │  Features:                     │  │ │
│  │  │  • APM via UDS             │  │  │  │  ✅ Sidecar injection          │  │ │
│  │  │  • Log collection          │  │  │  │  ✅ APM enabled                │  │ │
│  │  │  • Metrics collection      │  │  │  │  ❌ No SSI (manual)            │  │ │
│  │  │  • DogStatsD               │  │  │  │  ❌ Trace disabled (for now)   │  │ │
│  │  └────────────────────────────┘  │  │  │                                │  │ │
│  │                                  │  │  │  Image: spring-boot-demo:      │  │ │
│  └──────────────────────────────────┘  │  │         latest                 │  │ │
│                                        │  │  Replicas: 2                   │  │ │
│                                        │  │  Service: spring-boot-demo-    │  │ │
│                                        │  │           fargate-service      │  │ │
│                                        │  └────────────────────────────────┘  │ │
│                                        │            │                         │ │
│                                        │            │ localhost               │ │
│                                        │            ▼                         │ │
│                                        │  ┌────────────────────────────────┐  │ │
│                                        │  │  Datadog Agent Sidecar         │  │ │
│                                        │  │  (Injected by Operator)        │  │ │
│                                        │  │                                │  │ │
│                                        │  │  • APM collection              │  │ │
│                                        │  │  • Log collection              │  │ │
│                                        │  │  • Metrics forwarding          │  │ │
│                                        │  │  • DogStatsD                   │  │ │
│                                        │  └────────────────────────────────┘  │ │
│                                        │                                      │ │
│                                        └──────────────────────────────────────┘ │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                       Supporting Infrastructure                           │  │
│  │                                                                           │  │
│  │  • datadog-fargate-rbac.yaml - RBAC for Fargate namespace                 │  │
│  │  • fargate_ns_svc.yaml - Fargate namespace and service definitions        │  │
│  │  • datadog-secret-eks (Secret) - Datadog API key and cluster agent token  │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                    |                                            │
│                                    ▼                                            │
│                          ┌──────────────────────┐                               │
│                          │   Datadog Platform   │                               │
│                          │   (datadoghq.com)    │                               │
│                          │                      │                               │
│                          │  • APM Traces        │                               │
│                          │  • Custom Metrics    │                               │
│                          │  • Logs              │                               │
│                          │  • Infrastructure    │                               │
│                          └──────────────────────┘                               │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Components Breakdown

### 1. Datadog Operator (`agent-operator.yaml`)

**Purpose**: Central management for Datadog agents across EC2 and Fargate

**Key Features**:
- **DaemonSet Agent** (EC2 nodes): Version 7.70.0
- **Fargate Sidecar Injection**: Automatic injection via admission controller
- **SSI (Single Step Instrumentation)**: Java auto-instrumentation for non-Fargate pods
- **APM via Unix Domain Socket**: `/var/run/datadog/apm.socket`

**Configuration Highlights**:
```yaml
features:
  admissionController:
    agentSidecarInjection:
      enabled: true
      provider: fargate
  apm:
    instrumentation:
      enabled: true
      targets:
        - name: "ec2-java-target"
          namespaceSelector:
            matchNames: ["default", "fargate"]
          podSelector:
            matchExpressions:
              - key: "fargate"
                operator: "NotIn"
                values: ["true"]
    unixDomainSocketConfig:
      path: /var/run/datadog/apm.socket
```

---

### 2. EC2 Workload: `test-java-app` (SSI)

**Location**: `test-java-app/k8s/deployment.yaml`

**Namespace**: `default`

**Instrumentation Method**: Single Step Instrumentation (SSI) - Automatic

**Features**:
- ✅ **SSI Auto-injection**: Datadog Java library injected automatically
- ✅ **APM via UDS**: Traces sent via Unix Domain Socket
- ✅ **DaemonSet Agent**: Connects to node-level Datadog agent
- ❌ **No Sidecar**: Uses DaemonSet agent on EC2 node

**Key Configuration**:
```yaml
labels:
  admission.datadoghq.com/enabled: "true"
annotations:
  admission.datadoghq.com/java-lib.version: "v1"

env:
  - name: DD_TRACE_AGENT_URL
    value: "unix:///var/run/datadog/apm.socket"

volumeMounts:
  - name: apmsocketpath
    mountPath: /var/run/datadog
```

**Service**: `spring-boot-demo`  
**Replicas**: 2  
**Image**: `659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/spring-boot-demo:latest`

---

### 3. Fargate Workload: `dogstatsd-python-app` (Custom Instrumentation)

**Location**: `dogstatsd-py-app/dogstatsd.yaml`

**Namespace**: `fargate`

**Instrumentation Method**: Custom - Manual library integration

**Features**:
- ✅ **Custom Instrumentation**: `ddtrace` library manually added to app image
- ✅ **DogStatsD Custom Metrics**: Sends custom metrics via UDS
- ✅ **Sidecar Injection**: Datadog agent injected as sidecar
- ❌ **No SSI**: Manual instrumentation in application code

**Key Configuration**:
```yaml
labels:
  app: dogstatsd-python-app
  fargate: "true"
  agent.datadoghq.com/sidecar: fargate

env:
  - name: DD_APM_ENABLED
    value: "true"
  - name: DD_TRACE_ENABLED
    value: "true"
```

**Custom Metrics Sent**:
- `containerspod.isthebest` (increment)
- `failedatdoing.ecsfargatelogging` (decrement)

**Service**: `dogstatsd-python-app`  
**Type**: Pod (single instance)  
**Image**: `public.ecr.aws/r1n8o0r0/danny/fargate-py:latest`

---

### 4. Fargate Workload: `spring-boot-demo-fargate` (Sidecar Only)

**Location**: `spring-boot-fargate-deployment.yaml`

**Namespace**: `fargate`

**Instrumentation Method**: Sidecar injection, no SSI

**Features**:
- ✅ **Sidecar Injection**: Datadog agent runs as sidecar container
- ✅ **APM Ready**: Configured with `DD_AGENT_HOST=localhost`
- ❌ **No SSI**: Would need manual Spring Boot APM library
- ❌ **Traces Disabled**: `DD_TRACE_ENABLED=false` (no manual instrumentation)

**Key Configuration**:
```yaml
labels:
  app: spring-boot-demo-fargate
  fargate: "true"
  agent.datadoghq.com/sidecar: fargate

env:
  - name: DD_AGENT_HOST
    value: "localhost"
  - name: DD_TRACE_ENABLED
    value: "false"
```

**Service**: `spring-boot-demo-fargate-service`  
**Replicas**: 2  
**Image**: `659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/spring-boot-demo:latest`

**Note**: Same image as test-java-app, but running on Fargate without SSI

---

### 5. Supporting Infrastructure

#### `datadog-fargate-rbac.yaml`
**Purpose**: RBAC permissions for Datadog agent in Fargate namespace

**Resources**:
- ServiceAccount: `datadog-agent-fargate-service`
- ServiceAccount: `spring-boot-demo-fargate-service`
- ClusterRole: Read permissions for pods, services, endpoints
- ClusterRoleBinding: Links service accounts to cluster role

#### `fargate_ns_svc.yaml`
**Purpose**: Namespace and service definitions for Fargate workloads

**Resources**:
- Namespace: `fargate`
- Service: `spring-boot-demo-fargate-service` (port 8080)

#### `datadog-secret-eks` (Secret)
**Purpose**: Stores Datadog credentials

**Contains**:
- `api-key`: Datadog API key for sending data
- `token`: Cluster agent token for agent-to-agent communication

---

## Instrumentation Methods Comparison

| Method | Deployment | Namespace | Agent Type | Auto-Instrumentation | Manual Code | Use Case |
|--------|------------|-----------|------------|---------------------|-------------|----------|
| **SSI** | test-java-app | default | DaemonSet | ✅ Yes | ❌ No | EC2 nodes, zero code changes |
| **Custom** | dogstatsd-python-app | fargate | Sidecar | ❌ No | ✅ Yes | Custom metrics, full control |
| **Sidecar Only** | spring-boot-demo-fargate | fargate | Sidecar | ❌ No | ❌ No* | Infrastructure monitoring only |

*Note: spring-boot-demo-fargate could enable tracing by setting `DD_TRACE_ENABLED=true` and adding the Java APM library to the image.

---

## Network Flow

### EC2 Workload (test-java-app)
```
Application → Unix Domain Socket → DaemonSet Agent → Datadog Platform
            /var/run/datadog/apm.socket
```

### Fargate Workload (dogstatsd-python-app)
```
Application → localhost:8126 → Sidecar Agent → Datadog Platform
            (custom instrumentation)
```

### Fargate Workload (spring-boot-demo-fargate)
```
Application → localhost:8126 → Sidecar Agent → Datadog Platform
            (sidecar for logs/metrics only, no traces)
```

---

## Datadog Features by Workload

### test-java-app (EC2, SSI)
- ✅ APM Traces (auto-instrumented)
- ✅ Logs (stdout/stderr collection)
- ✅ Infrastructure Metrics
- ✅ Profiling (if enabled)
- ❌ Custom Metrics (unless added)

### dogstatsd-python-app (Fargate, Custom)
- ✅ APM Traces (manually instrumented)
- ✅ Logs (sidecar collection)
- ✅ Custom Metrics (DogStatsD)
- ✅ Infrastructure Metrics
- ❌ Automatic instrumentation

### spring-boot-demo-fargate (Fargate, Sidecar)
- ❌ APM Traces (disabled)
- ✅ Logs (sidecar collection)
- ✅ Infrastructure Metrics
- ❌ Custom Metrics
- ❌ Profiling

---

## Key Differences: EC2 vs Fargate

| Aspect | EC2 (default namespace) | Fargate (fargate namespace) |
|--------|------------------------|----------------------------|
| **Agent Deployment** | DaemonSet (node-level) | Sidecar (pod-level) |
| **APM Connection** | Unix Domain Socket | localhost TCP |
| **SSI Support** | ✅ Yes | ❌ No |
| **Log Collection** | Node-level agent | Sidecar or AWS Fluent Bit |
| **Resource Overhead** | Shared across pods | Per-pod overhead |
| **Scalability** | Node-limited | Per-pod isolation |
| **Setup Complexity** | Lower (SSI) | Higher (manual or sidecar) |

---

## Configuration Files Reference

```
config_files/
├── agent-operator.yaml                      # Datadog Operator setup
├── datadog-secret-eks.yaml                  # Datadog credentials
├── datadog-fargate-rbac.yaml                # Fargate RBAC
├── fargate_ns_svc.yaml                      # Fargate namespace/service
│
├── test-java-app/k8s/
│   └── deployment.yaml                      # EC2: SSI enabled
│
├── spring-boot-fargate-deployment.yaml      # Fargate: Sidecar only
│
└── dogstatsd-py-app/
    └── dogstatsd.yaml                       # Fargate: Custom instrumentation
```

---

## Deployment Order

1. **Namespace and RBAC**
   ```bash
   kubectl apply -f fargate_ns_svc.yaml
   kubectl apply -f datadog-fargate-rbac.yaml
   kubectl apply -f datadog-secret-eks.yaml
   ```

2. **Datadog Operator**
   ```bash
   kubectl apply -f agent-operator.yaml
   ```

3. **Applications** (any order)
   ```bash
   # EC2 workload with SSI
   kubectl apply -f test-java-app/k8s/deployment.yaml
   
   # Fargate workloads
   kubectl apply -f spring-boot-fargate-deployment.yaml
   kubectl apply -f dogstatsd-py-app/dogstatsd.yaml
   ```

---

## Verification Commands

### Check Datadog Operator
```bash
kubectl get datadogagent -A
kubectl get pods -n datadog
```

### Check EC2 Workload
```bash
kubectl get pods -n default -l app=spring-boot-demo
kubectl logs -n default <pod-name> | grep "dd.trace"
```

### Check Fargate Workloads
```bash
kubectl get pods -n fargate
kubectl describe pod -n fargate mydogstatsdpod
kubectl describe pod -n fargate <spring-boot-demo-fargate-pod>
```

### Check Sidecar Injection
```bash
# Should show 2 containers: app + datadog-agent
kubectl get pod -n fargate mydogstatsdpod -o jsonpath='{.spec.containers[*].name}'
```

---

## Troubleshooting

### SSI Not Working (test-java-app)
- Check label: `admission.datadoghq.com/enabled: "true"`
- Check annotation: `admission.datadoghq.com/java-lib.version: "v1"`
- Verify UDS mount: `volumeMounts` and `volumes` for `/var/run/datadog`
- Check operator SSI config targets non-Fargate pods

### Sidecar Not Injected (Fargate)
- Check label: `agent.datadoghq.com/sidecar: fargate`
- Verify admission controller is enabled
- Check namespace is `fargate`
- Review operator logs: `kubectl logs -n datadog <cluster-agent-pod>`

### Traces Not Appearing
- **EC2**: Check `DD_TRACE_AGENT_URL` points to UDS
- **Fargate**: Check `DD_AGENT_HOST=localhost`
- Verify Datadog API key is valid
- Check agent logs for connection errors

### Custom Metrics Not Showing
- Verify DogStatsD socket path matches agent configuration
- Check metric tags and naming conventions
- Review agent logs for metric submission

---

## Summary

This infrastructure demonstrates **three different Datadog integration patterns**:

1. **Automatic (SSI)**: Best for EC2 workloads, zero code changes
2. **Custom**: Full control for complex scenarios, requires code changes
3. **Infrastructure-only**: Basic monitoring without APM

Each approach has tradeoffs in terms of ease of setup, flexibility, and observability depth. Choose based on your workload type (EC2 vs Fargate) and monitoring requirements.

