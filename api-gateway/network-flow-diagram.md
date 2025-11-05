# KrakenD API Gateway Network Flow Diagram

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                EKS Cluster                                      │
│                                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐              │
│  │   Client Apps   │    │   Load Balancer │    │   External      │              │
│  │   (Browser/API) │    │   (ALB/NLB)     │    │   Services      │              │
│  └─────────┬───────┘    └─────────┬───────┘    └─────────────────┘              │
│            │                      │                                             │
│            │ HTTP/HTTPS           │                                             │
│            │                      │                                             │
│            ▼                      ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    KrakenD API Gateway                                  │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │  Pod: api-gateway-xxx (2 replicas)                              │    │    │
│  │  │  Image: 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/      │    │    │
│  │  │           api-gateway:latest                                    │    │    │
│  │  │                                                                 │    │    │
│  │  │  Ports:                                                         │    │    │
│  │  │  • 8080 (API) - Main API endpoints                              │    │    │
│  │  │  • 9090 (Metrics) - Prometheus metrics                          │    │    │
│  │  │                                                                 │    │    │
│  │  │  Environment Variables:                                         │    │    │
│  │  │  • DD_LOGS_INJECTION=true                                       │    │    │
│  │  │  • DD_APPSEC_ENABLED=true                                       │    │    │
│  │  │  • DD_TRACE_ENABLED=true                                        │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│            │                                                                    │
│            │ Service: api-gateway-svc                                           │
│            │ • Port 8080 → 8080 (API)                                           │
│            │ • Port 9090 → 9090 (Metrics)                                       │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                        Backend Services                                 │    │
│  │                                                                         │    │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │    │
│  │  │ auth-python-svc │  │ chat-node-svc   │  │ ranking-java-svc│          │    │
│  │  │ Port: 8000      │  │ Port: 8080      │  │ Port: 8081      │          │    │
│  │  │                 │  │                 │  │                 │          │    │
│  │  │ Endpoints:      │  │ Endpoints:      │  │ Endpoints:      │          │    │
│  │  │ • /auth/*       │  │ • /             │  │ • /             │          │    │
│  │  │ • /session/*    │  │ • /{path}       │  │ • /{path}       │          │    │
│  │  │ • /score        │  │                 │  │ • /rankings/*   │          │    │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                        Datadog Monitoring                               │    │
│  │                                                                         │    │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │    │
│  │  │ Datadog Agent   │  │ Datadog Cluster │  │ Datadog Operator│          │    │
│  │  │ Version: 7.70.0 │  │ Agent           │  │ Version: 1.16.0 │          │    │
│  │  │                 │  │                 │  │                 │          │    │
│  │  │ Integrations:   │  │                 │  │                 │          │    │
│  │  │ • krakend 1.0.1 │  │                 │  │                 │          │    │
│  │  │ • openmetrics   │  │                 │  │                 │          │    │
│  │  │   7.0.1         │  │                 │  │                 │          │    │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘          │    │
│  │            │                                                            │    │
│  │            │ Scrapes metrics from :9090/metrics                         │    │
│  │            │                                                            │    │
│  │            ▼                                                            │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │                Datadog Platform                                 │    │    │
│  │  │  • Dashboards                                                   │    │    │
│  │  │  • Alerts                                                       │    │    │
│  │  │  • APM Traces                                                   │    │    │
│  │  │  • Logs                                                         │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## API Endpoint Routing

### 1. Health Check Endpoint
```
GET /health
├── Backend: auth-python-svc:8000/
└── Static Response: {"status": "ok", "service": "api-gateway", "timestamp": "..."}
```

### 2. Authentication Service
```
GET/POST/DELETE /api/auth/{path}
└── Backend: auth-python-svc:8000/auth/{path}

GET /api/session/{path}
└── Backend: auth-python-svc:8000/session/{path}

POST /api/score
└── Backend: auth-python-svc:8000/score
```

### 3. Chat Service
```
GET /api/chat
└── Backend: chat-node-svc:8080/

GET/POST /api/chat/{path}
└── Backend: chat-node-svc:8080/{path}
```

### 4. Ranking Service
```
GET /api/ranking
└── Backend: ranking-java-svc:8081/

GET/POST /api/ranking/{path}
└── Backend: ranking-java-svc:8081/{path}

GET /rankings/{path}
└── Backend: ranking-java-svc:8081/rankings/{path}
```

### 5. Status Endpoint (Multi-backend)
```
GET /api/status
├── Backend Group "auth": auth-python-svc:8000/
├── Backend Group "chat": chat-node-svc:8080/
└── Backend Group "ranking": ranking-java-svc:8081/
```

## Monitoring & Observability

### KrakenD Metrics (Port 9090)
- **HTTP Server Metrics**: Request duration, response size, status codes
- **Backend Metrics**: Backend service performance, connection metrics
- **Go Runtime Metrics**: Memory usage, GC duration, goroutines
- **Process Metrics**: File descriptors, CPU usage

### Datadog Integration
- **Autodiscovery**: Automatically detects KrakenD pods via annotations
- **Metrics Collection**: Scrapes Prometheus metrics from :9090/metrics
- **APM Tracing**: Distributed tracing with DD_TRACE_ENABLED
- **Log Injection**: Structured logging with DD_LOGS_INJECTION
- **Security Monitoring**: Application security with DD_APPSEC_ENABLED

### Key Metrics Collected
```
krakend.api.http_server_duration.bucket
krakend.api.http_server_response_size.bucket
krakend.api.krakend_proxy_duration.bucket
krakend.api.krakend_backend_duration.bucket
krakend.api.go_memstats_heap_alloc_bytes
krakend.api.process_open_fds
```

## Network Flow Summary

1. **Client Request** → Load Balancer → KrakenD API Gateway (Port 8080)
2. **KrakenD Processing** → Route to appropriate backend service
3. **Backend Response** → KrakenD → Client
4. **Metrics Collection** → Datadog Agent scrapes Port 9090
5. **Monitoring** → Datadog Platform for dashboards, alerts, and APM

## Configuration Files
- **KrakenD Config**: `krakend.json` - API Gateway routing and telemetry
- **K8s Deployment**: `api-gateway.yaml` - Pod configuration with Datadog annotations
- **Docker Image**: `Dockerfile` - KrakenD 2.10.2 with custom configuration
- **Agent Config**: `agent-operator.yaml` - Datadog agent 7.70.0 with KrakenD integration














