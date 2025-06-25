#!/bin/bash

echo "=== Importing Route Table Associations ==="

# Import public subnet route table associations
echo "Importing public subnet associations..."
terragrunt import 'module.aws_vpc.aws_route_table_association.public[0]' subnet-0bc0fa720db3dcffd/rtb-0b0a69a4f6b6f7c74
terragrunt import 'module.aws_vpc.aws_route_table_association.public[1]' subnet-07f6cc20a8576121c/rtb-0b0a69a4f6b6f7c74
terragrunt import 'module.aws_vpc.aws_route_table_association.public[2]' subnet-0c4a4aa5f75a79015/rtb-0b0a69a4f6b6f7c74

# Import private subnet route table associations
echo "Importing private subnet associations..."
terragrunt import 'module.aws_vpc.aws_route_table_association.private[0]' subnet-02f3ff3d485d41d48/rtb-0c5c1f05e0ad96e37
terragrunt import 'module.aws_vpc.aws_route_table_association.private[1]' subnet-0576a98b8611cf446/rtb-0797903e067b72f2d
terragrunt import 'module.aws_vpc.aws_route_table_association.private[2]' subnet-02b6fa639bc3b0b6c/rtb-0f03cc6f670c0fe7a

# Import intra subnet route table associations
echo "Importing intra subnet associations..."
terragrunt import 'module.aws_vpc.aws_route_table_association.intra[0]' subnet-04c51cdd4a9dfbcd8/rtb-0e090e0cf2a3cd2e2
terragrunt import 'module.aws_vpc.aws_route_table_association.intra[1]' subnet-0e46d4fa2d0b9da96/rtb-0e090e0cf2a3cd2e2
terragrunt import 'module.aws_vpc.aws_route_table_association.intra[2]' subnet-0c0ce0867573cef02/rtb-0e090e0cf2a3cd2e2

echo "Done!"