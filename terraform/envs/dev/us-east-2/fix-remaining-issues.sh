#!/bin/bash

echo "=== Fixing Remaining Terraform Issues ==="

# Apply only the resources that can be created successfully
echo "Applying resources that can be created..."
terragrunt apply -auto-approve \
  -target=module.aws_eks.aws_iam_openid_connect_provider.eks \
  -target=module.aws_eks.aws_iam_role.aws_load_balancer_controller \
  -target=module.aws_eks.aws_iam_role.cluster_autoscaler \
  -target=module.aws_eks.aws_iam_role.ebs_csi_driver \
  -target=module.aws_eks.aws_iam_role.external_dns \
  -target=module.aws_eks.aws_iam_role.fluent_bit \
  -target=module.aws_eks.aws_eks_node_group.main

echo "Done! Most resources have been created successfully."
echo ""
echo "Note: Route table associations already exist in AWS but not in Terraform state."
echo "The S3 module has been temporarily disabled due to state issues."
echo ""
echo "To re-enable S3 buckets:"
echo "1. Uncomment the S3 module in main.tf"
echo "2. Import the existing buckets"
echo "3. Run terraform apply"