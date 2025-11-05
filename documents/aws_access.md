# EKS Access Setup Guide: From aws-vault SSO to Direct IAM User Access

## Problem Statement

### Initial Situation
- **Current Setup**: Using `aws-vault exec sso-tse-sandbox-account-admin --` before every kubectl command
- **Issue**: Required to prefix every kubectl command with the full aws-vault SSO command
- **Example**: `av kubectl get pods` instead of just `kubectl get pods`
- **Pain Points**:
  - Verbose command structure
  - Dependency on aws-vault for every operation
  - SSO role permissions issues with EKS cluster access
  - "Unauthorized" errors when trying to access EKS resources

### Why This Was Necessary
The original setup required the full command because:
1. **SSO Role Limitations**: The SSO role `AWSReservedSSO_account-admin_14e2cb225acd417b` wasn't properly configured in the EKS cluster's access control
2. **Authentication Method**: EKS cluster uses OIDC (OpenID Connect) authentication, not traditional aws-auth ConfigMap
3. **Permission Mapping**: The SSO role needed to be mapped to Kubernetes RBAC permissions

## Solution: Direct IAM User Access

### Overview
We created a dedicated IAM user with Administrator policy and configured it for direct EKS access, eliminating the need for aws-vault prefixes.

## Step-by-Step Process

### Step 1: Create IAM User with Administrator Policy
**Action**: Created IAM user `danny-aws-user` with Administrator policy
**Location**: AWS Console → IAM → Users → Create User
**Result**: User with full AWS permissions

### Step 2: Generate Access Keys
**Action**: Created access keys for the IAM user
**Location**: AWS Console → IAM → Users → danny-aws-user → Security credentials → Create access key
**Result**: 
- Access Key ID: `AKIAZTHNNY4I6E6FQ3N7`
- Secret Access Key: `[REDACTED]`

### Step 3: Add User to aws-vault
```bash
aws-vault add danny-aws-user
# Enter Access Key ID: AKIAZTHNNY4I6E6FQ3N7
# Enter Secret Access Key: [SECRET_KEY]
# Result: Added credentials to profile "danny-aws-user" in vault
```

### Step 4: Configure AWS CLI Profile
```bash
aws configure set aws_access_key_id AKIAZTHNNY4I6E6FQ3N7 --profile danny-aws-user
aws configure set aws_secret_access_key [SECRET_KEY] --profile danny-aws-user
aws configure set default.region ap-northeast-2 --profile danny-aws-user
```

### Step 5: Verify IAM User Authentication
```bash
aws sts get-caller-identity --profile danny-aws-user
```
**Result**:
```json
{
    "UserId": "AIDAZTHNNY4IZABNE7THB",
    "Account": "659775407889",
    "Arn": "arn:aws:iam::659775407889:user/danny-aws-user"
}
```

### Step 6: Update kubeconfig for EKS
```bash
aws eks update-kubeconfig --region ap-northeast-2 --name danny-eks-cluster --profile danny-aws-user
```
**Result**: `Updated context arn:aws:eks:ap-northeast-2:659775407889:cluster/danny-eks-cluster in /Users/danny.park/.kube/config`

### Step 7: Create EKS Access Entry
**Problem**: Initial kubectl access resulted in "Unauthorized" error
**Root Cause**: IAM user not configured in EKS cluster's access control
**Solution**: Create access entry using AWS CLI

```bash
aws eks create-access-entry \
  --cluster-name danny-eks-cluster \
  --principal-arn arn:aws:iam::659775407889:user/danny-aws-user \
  --region ap-northeast-2 \
  --profile danny-aws-user
```

**Result**:
```json
{
    "accessEntry": {
        "clusterName": "danny-eks-cluster",
        "principalArn": "arn:aws:iam::659775407889:user/danny-aws-user",
        "accessEntryArn": "arn:aws:eks:ap-northeast-2:659775407889:access-entry/danny-eks-cluster/user/659775407889/danny-aws-user/4cccba6e-3201-29d8-0034-f126d8d82410",
        "username": "arn:aws:iam::659775407889:user/danny-aws-user",
        "type": "STANDARD"
    }
}
```

### Step 8: Associate Admin Policy
```bash
aws eks associate-access-policy \
  --cluster-name danny-eks-cluster \
  --principal-arn arn:aws:iam::659775407889:user/danny-aws-user \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region ap-northeast-2 \
  --profile danny-aws-user
```

**Result**:
```json
{
    "clusterName": "danny-eks-cluster",
    "principalArn": "arn:aws:iam::659775407889:user/danny-aws-user",
    "associatedAccessPolicy": {
        "policyArn": "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
        "accessScope": {
            "type": "cluster"
        }
    }
}
```

### Step 9: Verify Access
```bash
kubectl get pods
kubectl get nodes
kubectl get pods --all-namespaces
```

**Results**:
- ✅ `kubectl get pods`: No resources found in default namespace
- ✅ `kubectl get nodes`: 3 nodes (2 regular + 1 Fargate)
- ✅ `kubectl get pods --all-namespaces`: 17 pods across multiple namespaces

## Key Technical Details

### Authentication Method
- **Cluster Type**: EKS with OIDC authentication
- **OIDC Issuer**: `https://oidc.eks.ap-northeast-2.amazonaws.com/id/8F9574A5E048B878E7F8154787E47DA5`
- **Access Method**: EKS Access Entries (modern approach) vs aws-auth ConfigMap (legacy)

### Cluster Information
- **Account**: 659775407889
- **Region**: ap-northeast-2 (Seoul)
- **Cluster Name**: danny-eks-cluster
- **Nodes**: 3 (2 regular EC2 + 1 Fargate)

## Troubleshooting Common Issues

### Issue 1: "Unauthorized" Error
**Cause**: IAM user not configured in EKS access control
**Solution**: Create access entry and associate with admin policy

### Issue 2: MFA Required
**Cause**: IAM user configured with MFA requirement
**Solution**: Use AWS CLI profile instead of aws-vault exec

### Issue 3: SSO Role Permission Issues
**Cause**: SSO role not properly mapped to EKS permissions
**Solution**: Use dedicated IAM user with explicit EKS access configuration

## Security Considerations

### IAM User Security
- ✅ Administrator policy provides full AWS access
- ✅ Access keys stored securely in aws-vault
- ✅ MFA can be enabled if required
- ✅ Keys can be rotated regularly

### EKS Access Security
- ✅ Access entry provides explicit cluster access
- ✅ Admin policy grants necessary Kubernetes permissions
- ✅ No dependency on external SSO systems
- ✅ Direct authentication with cluster

## Benefits Achieved

1. **Simplified Commands**: No more verbose aws-vault prefixes
2. **Direct Access**: kubectl commands work without additional setup
3. **Reliable Authentication**: No SSO dependency or permission issues
4. **Full Permissions**: Complete cluster admin access
5. **Better Developer Experience**: Standard kubectl workflow

## Future Maintenance

### Key Rotation
```bash
# Generate new access keys
aws iam create-access-key --user-name danny-aws-user

# Update aws-vault
aws-vault add danny-aws-user

# Update AWS CLI profile
aws configure set aws_access_key_id [NEW_KEY] --profile danny-aws-user
```

### Access Verification
```bash
# Verify AWS access
aws sts get-caller-identity --profile danny-aws-user

# Verify EKS access
kubectl get nodes
kubectl auth can-i get pods --all-namespaces
```

## Conclusion

This setup successfully eliminated the need for aws-vault prefixes while maintaining secure access to the EKS cluster. The IAM user approach provides a clean, reliable method for EKS access that integrates seamlessly with standard kubectl workflows.

**Final Result**: Direct kubectl access without aws-vault dependencies, enabling efficient Kubernetes cluster management.
