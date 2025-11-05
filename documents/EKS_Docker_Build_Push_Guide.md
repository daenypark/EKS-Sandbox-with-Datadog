# EKS Docker Build and Push Guide

## Overview

This document covers the complete process of building Docker images for EKS deployment, including handling architecture compatibility issues and pushing to AWS ECR (Elastic Container Registry).

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Common Issues and Solutions](#common-issues-and-solutions)
3. [Step-by-Step Process](#step-by-step-process)
4. [Architecture Compatibility](#architecture-compatibility)
5. [ECR Setup and Management](#ecr-setup-and-management)
6. [Deployment Configuration](#deployment-configuration)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

## Prerequisites

- Docker Desktop running
- AWS CLI configured with appropriate permissions
- kubectl configured for EKS cluster access
- Java application built (Maven/Gradle)

## Common Issues and Solutions

### Issue 1: ModuleNotFoundError in Java Application
**Problem**: Getting `ModuleNotFoundError: No module named 'datadog'` in a Java Spring Boot application
**Root Cause**: Deployment YAML was incorrectly configured to use Python image instead of Java application
**Solution**: Fix deployment.yaml to use the correct Java application image

### Issue 2: Architecture Mismatch
**Problem**: `exec format error` when running containers on EKS
**Root Cause**: Docker image built on ARM64 (M1 Mac) but EKS nodes run on x86_64
**Solution**: Build image with `--platform linux/amd64` flag

### Issue 3: Image Pull Errors
**Problem**: `ErrImageNeverPull` or `ErrImagePullBackOff`
**Root Cause**: Image not available in registry or incorrect pull policy
**Solution**: Push image to ECR and configure correct pull policy

## Step-by-Step Process

### Step 1: Build the Application

```bash
# Navigate to your application directory
cd /path/to/your/java-app

# Build the Java application (if using Maven)
mvn clean package -DskipTests

# Verify the JAR file is created
ls -la target/*.jar
```

### Step 2: Create Dockerfile

```dockerfile
FROM openjdk:17-jdk-slim

WORKDIR /app

# Copy the JAR file
COPY target/demo-0.0.1-SNAPSHOT.jar app.jar

# Expose port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Step 3: Build Docker Image with Correct Architecture

```bash
# Build for EKS (x86_64 architecture)
docker build --platform linux/amd64 -t your-app-name:latest .

# Verify the image was built
docker images | grep your-app-name
```

### Step 4: Set Up ECR Repository

```bash
# Create ECR repository
aws ecr create-repository \
  --repository-name your-app-name \
  --region ap-northeast-2 \
  --profile your-aws-profile

# Login to ECR
aws ecr get-login-password \
  --region ap-northeast-2 \
  --profile your-aws-profile | \
  docker login \
  --username AWS \
  --password-stdin 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com
```

### Step 5: Tag and Push Image

```bash
# Tag the image for ECR
docker tag your-app-name:latest \
  659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/your-app-name:latest

# Push to ECR
docker push 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/your-app-name:latest
```

### Step 6: Update Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-app-name
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: your-app-name
  template:
    metadata:
      labels:
        app: your-app-name
    spec:
      containers:
      - name: your-app-name
        image: 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/your-app-name:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        env:
        - name: DD_SERVICE
          value: "your-app-name"
        - name: DD_ENV
          value: "test"
        - name: DD_VERSION
          value: "1.0.0"
```

### Step 7: Deploy to EKS

```bash
# Apply the deployment
kubectl apply -f k8s/

# Check pod status
kubectl get pods -l app=your-app-name

# Check logs
kubectl logs -l app=your-app-name
```

## Architecture Compatibility

### Understanding the Problem

- **Local Development**: Often on ARM64 (M1/M2 Macs)
- **EKS Nodes**: Run on x86_64 (Intel/AMD)
- **Solution**: Build images with `--platform linux/amd64`

### Build Commands by Architecture

```bash
# For x86_64 (EKS compatible)
docker build --platform linux/amd64 -t app:latest .

# For ARM64 (M1/M2 Mac native)
docker build --platform linux/arm64 -t app:latest .

# For multi-platform (both)
docker buildx build --platform linux/amd64,linux/arm64 -t app:latest .
```

### Verification

```bash
# Check image architecture
docker inspect your-image:latest | grep Architecture

# Expected output for EKS:
# "Architecture": "amd64"
```

## ECR Setup and Management

### Repository Creation

```bash
# Create repository with specific settings
aws ecr create-repository \
  --repository-name your-app-name \
  --region ap-northeast-2 \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 \
  --profile your-aws-profile
```

### Repository Management

```bash
# List repositories
aws ecr describe-repositories --region ap-northeast-2 --profile your-aws-profile

# List images in repository
aws ecr list-images \
  --repository-name your-app-name \
  --region ap-northeast-2 \
  --profile your-aws-profile

# Delete repository (careful!)
aws ecr delete-repository \
  --repository-name your-app-name \
  --region ap-northeast-2 \
  --force \
  --profile your-aws-profile
```

### Authentication

```bash
# Login to ECR
aws ecr get-login-password \
  --region ap-northeast-2 \
  --profile your-aws-profile | \
  docker login \
  --username AWS \
  --password-stdin 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com

# Verify login
docker pull 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/your-app-name:latest
```

## Deployment Configuration

### Image Pull Policies

```yaml
# Always pull (recommended for development)
imagePullPolicy: Always

# Pull if not present (recommended for production)
imagePullPolicy: IfNotPresent

# Never pull (only for local development)
imagePullPolicy: Never
```

## Troubleshooting

### Common Error Messages

#### 1. `exec format error`
```bash
# Error: exec /usr/local/openjdk-17/bin/java: exec format error
# Solution: Rebuild with correct platform
docker build --platform linux/amd64 -t app:latest .
```

#### 2. `ErrImageNeverPull`
```bash
# Error: Container image "app:latest" is not present with pull policy of Never
# Solution: Change pull policy or push to registry
imagePullPolicy: Always
```

#### 3. `ErrImagePullBackOff`
```bash
# Error: Failed to pull image
# Solution: Check image exists in registry and authentication
aws ecr describe-images --repository-name your-app-name
```

#### 4. `ModuleNotFoundError`
```bash
# Error: ModuleNotFoundError: No module named 'datadog'
# Solution: Check deployment.yaml uses correct image (Java, not Python)
```

### Debugging Commands

```bash
# Check pod status
kubectl get pods -l app=your-app-name

# Describe pod for detailed info
kubectl describe pod your-pod-name

# Check pod logs
kubectl logs your-pod-name

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp

# Check image details
docker inspect your-image:latest

# Test image locally
docker run -p 8080:8080 your-image:latest
```

## Best Practices

### 1. Image Tagging Strategy

```bash
# Use semantic versioning
docker tag app:latest 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/app:v1.0.0

# Use commit hash
docker tag app:latest 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/app:$(git rev-parse --short HEAD)

# Use environment
docker tag app:latest 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/app:dev
```

### 2. Multi-Stage Builds

```dockerfile
# Build stage
FROM maven:3.8-openjdk-17 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

# Runtime stage
FROM openjdk:17-jdk-slim
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 3. Security Best Practices

```bash
# Scan images for vulnerabilities
aws ecr describe-image-scan-findings \
  --repository-name your-app-name \
  --image-id imageTag=latest

# Use non-root user
FROM openjdk:17-jdk-slim
RUN addgroup --system spring && adduser --system spring --ingroup spring
USER spring:spring
```

### 4. CI/CD Integration

```yaml
# GitHub Actions example
- name: Build and push
  run: |
    docker build --platform linux/amd64 -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
    docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
```

## Real-World Example

### Our Spring Boot Application

```bash
# 1. Build Java application
cd test-java-app
mvn clean package -DskipTests

# 2. Build Docker image
docker build --platform linux/amd64 -t spring-boot-demo:latest .

# 3. Create ECR repository
aws ecr create-repository --repository-name spring-boot-demo --region ap-northeast-2 --profile danny-aws-user

# 4. Login to ECR
aws ecr get-login-password --region ap-northeast-2 --profile danny-aws-user | docker login --username AWS --password-stdin 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com

# 5. Tag and push
docker tag spring-boot-demo:latest 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/spring-boot-demo:latest
docker push 659775407889.dkr.ecr.ap-northeast-2.amazonaws.com/spring-boot-demo:latest

# 6. Deploy to EKS
kubectl apply -f k8s/
kubectl get pods -l app=spring-boot-demo
```

## Summary

This guide covers the complete process of building and deploying Docker images to EKS, including:

- ✅ **Architecture compatibility** (ARM64 vs x86_64)
- ✅ **ECR setup and management**
- ✅ **Proper deployment configuration**
- ✅ **Troubleshooting common issues**
- ✅ **Best practices for production**

The key takeaway is to always build images with `--platform linux/amd64` when targeting EKS, and use ECR for reliable image storage and distribution.
