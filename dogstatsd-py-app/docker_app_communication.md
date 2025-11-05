# DogStatsD App Communication Architecture

## Overview

This document describes the communication flow between the DogStatsD Python application, Datadog sidecar agent, and Datadog backend in an EKS Fargate environment.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           EKS Fargate Pod (mydogstatsdpod)                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                         │    │
│  │  ┌─────────────────┐    ┌─────────────────────────────────────────┐    │    │
│  │  │                 │    │                                         │    │    │
│  │  │  DogStatsD App  │    │     Datadog Sidecar Agent               │    │    │
│  │  │  (Python)       │    │     (datadog-agent-injected)            │    │    │
│  │  │                 │    │                                         │    │    │
│  │  │  • ddtrace      │    │  • DogStatsD Listener                   │    │    │
│  │  │  • datadog lib  │    │  • APM Agent                            │    │    │
│  │  │  • Custom       │    │  • Logs Agent                           │    │    │
│  │  │    Metrics      │    │  • Forwarder                            │    │    │
│  │  │  • Traces       │    │                                         │    │    │
│  │  └─────────────────┘    └─────────────────────────────────────────┘    │    │
│  │           │                                    │                       │    │
│  │           │                                    │                       │    │
│  │           │ 1. DogStatsD Metrics               │                       │    │
│  │           │    (UDS Socket)                    │                       │    │
│  │           ├────────────────────────────────────►│                       │    │
│  │           │    /var/run/datadog/dsd.socket     │                       │    │
│  │           │                                    │                       │    │
│  │           │ 2. DogStatsD Metrics               │                       │    │
│  │           │    (UDP)                           │                       │    │
│  │           ├────────────────────────────────────►│                       │    │
│  │           │    127.0.0.1:8125                  │                       │    │
│  │           │                                    │                       │    │
│  │           │ 3. APM Traces                      │                       │    │
│  │           │    (HTTP)                          │                       │    │
│  │           ├────────────────────────────────────►│                       │    │
│  │           │    localhost:8126                  │                       │    │
│  │           │                                    │                       │    │
│  │           │ 4. Application Logs                │                       │    │
│  │           │    (stdout/stderr)                 │                       │    │
│  │           ├────────────────────────────────────►│                       │    │
│  │           │    Container Logs                  │                       │    │
│  │           │                                    │                       │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ 5. Aggregated Data
                                    │    • Metrics
                                    │    • Traces  
                                    │    • Logs
                                    │    • Infrastructure
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           Datadog Backend                                       │
│                                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                │
│  │                 │  │                 │  │                 │                │
│  │   Metrics API   │  │   APM API       │  │   Logs API      │                │
│  │                 │  │                 │  │                 │                │
│  │ • Custom Metrics│  │ • Traces        │  │ • Application   │                │
│  │ • System Metrics│  │ • Spans         │  │   Logs          │                │
│  │ • Infrastructure│  │ • Performance   │  │ • Container     │                │
│  │                 │  │   Data          │  │   Logs          │                │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                │
│           │                     │                     │                       │
│           └─────────────────────┼─────────────────────┘                       │
│                                 │                                             │
│                                 ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    Datadog Platform                                     │    │
│  │                                                                         │    │
│  │  • Dashboards & Visualizations                                          │    │
│  │  • Alerting & Monitoring                                                │    │
│  │  │  • containerspod.isthebest                                           │    │
│  │  │  • failedatdoing.ecsfargatelogging                                   │    │
│  │  • APM Service Map                                                      │    │
│  │  • Log Analytics                                                        │    │
│  │  • Infrastructure Overview                                              │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Communication Flow Details

### 1. DogStatsD Metrics (UDS Socket)
- **Path**: `/var/run/datadog/dsd.socket`
- **Protocol**: Unix Domain Socket (UDS)
- **Data**: Custom metrics (`containerspod.isthebest`, `failedatdoing.ecsfargatelogging`)
- **Volume**: 1,031 packets, 1,011,193 bytes
- **Advantages**: 
  - Lower latency
  - Higher throughput
  - More secure (local filesystem)

### 2. DogStatsD Metrics (UDP)
- **Path**: `127.0.0.1:8125`
- **Protocol**: UDP
- **Data**: Additional metrics and system metrics
- **Volume**: 23,729 packets, 14,847,650 bytes
- **Advantages**:
  - Standard DogStatsD protocol
  - Compatible with external tools
  - Fallback communication method

### 3. APM Traces
- **Path**: `localhost:8126`
- **Protocol**: HTTP/HTTPS
- **Data**: Distributed traces and spans
- **Volume**: 6 traces, 6 spans, 2,124 bytes
- **Features**:
  - Request tracing
  - Performance monitoring
  - Service dependency mapping

### 4. Application Logs
- **Path**: Container stdout/stderr
- **Protocol**: Container logging
- **Data**: Application log messages
- **Collection**: Via kubelet API logging
- **Configuration**: `DD_ADMISSION_CONTROLLER_AGENT_SIDECAR_KUBELET_API_LOGGING_ENABLED: "true"`

### 5. Backend Transmission
- **Metrics**: Sent to `https://app.datadoghq.com/api/v1/series`
- **Traces**: Sent to `https://trace.agent.datadoghq.com`
- **Logs**: Sent to `https://agent-http-intake.logs.datadoghq.com`

## Key Statistics (Verified)

Based on the agent status output:

- **Total DogStatsD Metrics**: 68,814 samples processed
- **Total Series Flushed**: 169,597
- **UDP Packets**: 23,729
- **UDS Packets**: 1,031
- **APM Traces**: Successfully received and processed
- **Communication**: Both UDS and UDP methods working simultaneously

## Application Configuration

### Python Application (app.py)
```python
from datadog import initialize, statsd
from ddtrace import tracer
import time
import os

# Initialize DogStatsD
options = {
    "statsd_socket_path": "/var/run/datadog/dsd.socket"
}
initialize(**options)

print("Starting app with tracing...")

while True:
    # Generate a simple trace
    with tracer.trace("simple.operation", service="dogstatsd-python-app") as span:
        span.set_tag("environment", "fargate")
        
        # Send metrics
        statsd.increment('containerspod.isthebest', tags=["environment:lowkey"])
        statsd.decrement('failedatdoing.ecsfargatelogging', tags=["environment:sad"])
        
        print("Sent metrics and generated trace")
        time.sleep(10)
```

### Docker Configuration
```dockerfile
FROM python:3
WORKDIR /usr/src/app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install ddtrace
RUN pip install --upgrade pip
RUN pip install datadog
COPY app.py ./app.py
CMD ["ddtrace-run", "python", "app.py"]
```

### Kubernetes Pod Configuration
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mydogstatsdpod
  namespace: fargate
  labels:
    app: spring-boot-demo-fargate
    version: v1
    fargate: "true"
    agent.datadoghq.com/sidecar: fargate

spec:
  shareProcessNamespace: true
  serviceAccountName: datadog-agent-fargate-service
  containers:
  - name: mydogstatsdpod
    image: public.ecr.aws/r1n8o0r0/danny/fargate-py:latest
    imagePullPolicy: Always
    env:
    # APM Configuration
    - name: DD_APM_ENABLED
      value: "true"
    - name: DD_TRACE_ENABLED
      value: "true"
    - name: DD_PROFILING_ENABLED
      value: "true"
    - name: DD_LOGS_INJECTION
      value: "true"
    - name: DD_SERVICE
      value: "dogstatsd-python-app"
    - name: DD_ENV
      value: "fargate"
    - name: DD_VERSION
      value: "1.0.0"
```

## Verification Commands

### Check Socket Communication
```bash
# Verify Unix socket exists
kubectl exec mydogstatsdpod -n fargate -c mydogstatsdpod -- ls -la /var/run/datadog/

# Test UDP communication
kubectl exec mydogstatsdpod -n fargate -c mydogstatsdpod -- python3 -c "
import socket
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.sendto(b'test.metric:1|c', ('127.0.0.1', 8125))
print('Sent UDP metric to 127.0.0.1:8125')
sock.close()
"

# Test Unix socket communication
kubectl exec mydogstatsdpod -n fargate -c mydogstatsdpod -- python3 -c "
import socket
sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
sock.sendto(b'test.metric.uds:1|c', '/var/run/datadog/dsd.socket')
print('Sent UDS metric to /var/run/datadog/dsd.socket')
sock.close()
"
```

### Check Agent Status
```bash
# Get comprehensive agent status
kubectl exec mydogstatsdpod -n fargate -c datadog-agent-injected -- agent status

# Check DogStatsD specific logs
kubectl logs mydogstatsdpod -n fargate -c datadog-agent-injected | grep -i "dogstatsd\|metric"

# Check application logs
kubectl logs mydogstatsdpod -n fargate -c mydogstatsdpod
```

## Benefits of This Architecture

1. **High Performance**: Unix Domain Socket provides low-latency communication
2. **Reliability**: Dual communication paths (UDS + UDP) ensure redundancy
3. **Observability**: Complete telemetry coverage (metrics, traces, logs)
4. **Fargate Compatibility**: Works seamlessly in serverless container environment
5. **Security**: Local socket communication reduces network exposure

## Troubleshooting

### Common Issues
1. **Socket Not Found**: Ensure Datadog sidecar is properly injected
2. **Permission Denied**: Check socket permissions and pod security context
3. **Metrics Not Appearing**: Verify agent status and check for parse errors
4. **APM Connection Issues**: Confirm DD_AGENT_HOST environment variable

### Debug Steps
1. Check pod status and container readiness
2. Verify socket existence and permissions
3. Review agent logs for errors
4. Test communication with manual metric sending
5. Confirm backend connectivity and API key validity

## References

- [Datadog DogStatsD Documentation](https://docs.datadoghq.com/developers/dogstatsd/)
- [Datadog APM Documentation](https://docs.datadoghq.com/tracing/)
- [EKS Fargate Integration](https://docs.datadoghq.com/integrations/eks_fargate/)
- [Datadog Agent Configuration](https://docs.datadoghq.com/agent/)
