#!/bin/bash

echo "Testing APM Instrumentation for Spring Boot Demo"
SERVICE_URL="http://localhost:8080"

# Test basic endpoint
echo "Testing basic endpoint..."
curl -s "$SERVICE_URL/" | jq .

# Test health endpoints
echo -e "\nTesting health endpoints..."
curl -s "$SERVICE_URL/actuator/health/liveness" | jq .
curl -s "$SERVICE_URL/actuator/health/readiness" | jq .

# Generate some traffic for APM
echo -e "\nGenerating traffic for APM testing..."
for i in {1..10}; do
    echo "Request $i"
    curl -s "$SERVICE_URL/" > /dev/null
    sleep 1
done

echo -e "\nCheck your Datadog APM dashboard for traces and metrics."
echo "You should see:"
echo "- Service: spring-boot-demo"
echo "- Environment: test"
echo "- Version: 1.0.0"
echo "- Traces from the HTTP requests"
