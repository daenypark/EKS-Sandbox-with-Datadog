#!/bin/bash

echo "Building Spring Boot Application with Cloud Native Buildpacks..."
echo "=============================================================="

# Check if Maven is installed
if ! command -v mvn &> /dev/null; then
    echo "Maven is not installed. Please install Maven first."
    exit 1
fi

# Clean and build the project
echo "Building Spring Boot application..."
mvn clean package -DskipTests

# Build Docker image using Cloud Native Buildpacks
echo "Building Docker image with Cloud Native Buildpacks..."
./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=spring-k8s/hello-spring-k8s

echo "Build completed successfully!"
echo "Docker image: spring-k8s/hello-spring-k8s"
echo ""
echo "To deploy to Kubernetes:"
echo "kubectl apply -f k8s/"
echo ""
echo "To test locally:"
echo "docker run -p 8080:8080 spring-k8s/hello-spring-k8s"
