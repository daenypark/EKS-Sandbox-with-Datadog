# Spring Boot Demo Application for APM Testing

This is a simple Spring Boot application designed to test Datadog APM single-step instrumentation.

## Features

- REST API endpoints for testing different scenarios
- Health checks and metrics via Spring Boot Actuator
- Simulated slow operations and errors
- Ready for Kubernetes deployment

## API Endpoints

- `GET /api/hello` - Simple hello endpoint
- `GET /api/slow` - Simulates slow operations (500-2500ms)
- `GET /api/error` - Randomly throws errors
- `POST /api/data` - Accepts JSON data
- `GET /api/health` - Health check endpoint
- `GET /actuator/health` - Spring Boot Actuator health check

## Building the Application

### Prerequisites
- Java 17
- Maven
- Docker

### Build Steps

1. **Build the application:**
   ```bash
   chmod +x build.sh
   ./build.sh
   ```

2. **Or manually:**
   ```bash
   mvn clean package -DskipTests
   docker build -t spring-boot-demo:latest .
   ```

## Testing Locally

1. **Run the application:**
   ```bash
   docker run -p 8080:8080 spring-boot-demo:latest
   ```

2. **Test the endpoints:**
   ```bash
   chmod +x test-apm.sh
   ./test-apm.sh
   ```

3. **Manual testing:**
   ```bash
   curl http://localhost:8080/api/hello
   curl http://localhost:8080/api/slow
   curl http://localhost:8080/api/error
   curl -X POST http://localhost:8080/api/data \
        -H "Content-Type: application/json" \
        -d '{"test": "data"}'
   ```

## Deploying to Kubernetes

1. **Apply the Kubernetes manifests:**
   ```bash
   kubectl apply -f k8s/
   ```

2. **Check the deployment:**
   ```bash
   kubectl get pods -l app=spring-boot-demo
   kubectl get svc spring-boot-demo-service
   ```

3. **Port forward to access the service:**
   ```bash
   kubectl port-forward svc/spring-boot-demo-service 8080:80
   ```

4. **Test the deployed application:**
   ```bash
   curl http://localhost:8080/api/hello
   ```

## APM Testing

The application is configured with Datadog environment variables:
- `DD_SERVICE`: spring-boot-demo
- `DD_ENV`: test
- `DD_VERSION`: 1.0.0

### Expected APM Data

1. **Traces**: HTTP requests to all endpoints
2. **Metrics**: Response times, error rates, throughput
3. **Logs**: Application logs with correlation IDs
4. **Service Map**: Service dependencies and relationships

### Verification Steps

1. **Check Datadog APM Dashboard:**
   - Go to APM > Services
   - Look for "spring-boot-demo" service
   - Verify traces are being collected

2. **Check Service Map:**
   - View service dependencies
   - Verify request flows

3. **Check Metrics:**
   - Response times
   - Error rates
   - Throughput

## Troubleshooting

1. **Application not starting:**
   - Check logs: `kubectl logs -l app=spring-boot-demo`
   - Verify health checks: `curl http://localhost:8080/actuator/health`

2. **No APM data:**
   - Verify Datadog agent is running: `kubectl get pods -n datadog`
   - Check agent logs: `kubectl logs -n datadog -l app=datadog-agent`
   - Verify APM is enabled in agent configuration

3. **Network issues:**
   - Check service connectivity: `kubectl get endpoints spring-boot-demo-service`
   - Verify ingress configuration if using ingress
