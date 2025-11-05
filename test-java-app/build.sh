#!/bin/bash

echo "Building Spring Boot Demo Application..."

# Check if Maven is installed
if ! command -v mvn &> /dev/null; then
    echo "Maven is not installed. Please install Maven first."
    exit 1
fi

# Clean and build the project
mvn clean package -DskipTests

# Build Docker image
docker build -t spring-boot-demo:latest .

echo "Build completed successfully!"
echo "Docker image: spring-boot-demo:latest"
echo ""
echo "To deploy to Kubernetes:"
echo "kubectl apply -f k8s/"
echo ""
echo "To test locally:"
echo "docker run -p 8080:8080 spring-boot-demo:latest"
