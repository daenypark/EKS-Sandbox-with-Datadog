# Building and Pushing Docker Images to ECR Public

Simple guide to build custom Docker images and push them to Amazon ECR Public.

## 🚀 Quick Steps

### 1. Build Image
```bash
docker buildx build --platform linux/amd64 -t your-app-name:latest .
```

### 2. Create ECR Public Repository
```bash
aws ecr-public create-repository --repository-name your-repo-name --region us-east-1
```

### 3. Login to ECR Public
```bash
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
```

### 4. Tag Image
```bash
docker tag your-app-name:latest public.ecr.aws/REGISTRY_ID/REPO_NAME:latest
```

### 5. Push Image
```bash
docker push public.ecr.aws/REGISTRY_ID/REPO_NAME:latest
```

## 📋 Prerequisites

- Docker installed and running
- AWS CLI configured
- ECR Public permissions

## 🔍 Get Repository Info

```bash
aws ecr-public describe-repositories --region us-east-1
```

## ⚠️ Important Notes

- ECR Public is **only available in us-east-1** region
- Use `--platform linux/amd64` for EKS compatibility
- Repository names are globally unique across all AWS accounts

## 🌐 Your Image URL

After pushing, your image will be available at:
```
public.ecr.aws/REGISTRY_ID/REPO_NAME:latest
```

Anyone can pull it with:
```bash
docker pull public.ecr.aws/REGISTRY_ID/REPO_NAME:latest
```
