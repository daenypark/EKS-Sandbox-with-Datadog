#!/bin/bash

# IAM User Setup for EKS Access (Account: 659775407889)
# This script creates an IAM user with necessary EKS permissions

USER_NAME="danny-eks-user"
POLICY_NAME="DannyEKSUserPolicy"
CLUSTER_NAME="danny-eks-cluster"
ACCOUNT_ID="659775407889"

echo "Creating IAM user: $USER_NAME"

# Create the IAM user
aws iam create-user --user-name $USER_NAME

# Create inline policy for EKS access
cat > eks-user-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters",
                "eks:AccessKubernetesApi",
                "eks:DescribeNodegroup",
                "eks:ListNodegroups"
            ],
            "Resource": [
                "arn:aws:eks:*:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}",
                "arn:aws:eks:*:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:GetRole",
                "iam:PassRole"
            ],
            "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/eksctl-*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVpcs"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Attach the policy to the user
aws iam put-user-policy \
    --user-name $USER_NAME \
    --policy-name $POLICY_NAME \
    --policy-document file://eks-user-policy.json

# Create access keys for the user
echo "Creating access keys for user: $USER_NAME"
aws iam create-access-key --user-name $USER_NAME

echo "IAM user setup complete!"
echo "Save the AccessKeyId and SecretAccessKey securely."
echo "You can now configure kubectl to use these credentials."












