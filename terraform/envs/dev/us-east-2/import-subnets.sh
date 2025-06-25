#!/bin/bash

echo "=== Importing AWS VPC Subnets ==="

# Import public subnets
terragrunt import 'module.aws_vpc.aws_subnet.public[0]' subnet-0bc0fa720db3dcffd
terragrunt import 'module.aws_vpc.aws_subnet.public[1]' subnet-07f6cc20a8576121c
terragrunt import 'module.aws_vpc.aws_subnet.public[2]' subnet-0c4a4aa5f75a79015

# Import private subnets
terragrunt import 'module.aws_vpc.aws_subnet.private[0]' subnet-02f3ff3d485d41d48
terragrunt import 'module.aws_vpc.aws_subnet.private[1]' subnet-0576a98b8611cf446
terragrunt import 'module.aws_vpc.aws_subnet.private[2]' subnet-02b6fa639bc3b0b6c

# Import intra subnets
terragrunt import 'module.aws_vpc.aws_subnet.intra[0]' subnet-04c51cdd4a9dfbcd8
terragrunt import 'module.aws_vpc.aws_subnet.intra[1]' subnet-0e46d4fa2d0b9da96
terragrunt import 'module.aws_vpc.aws_subnet.intra[2]' subnet-0c0ce0867573cef02

echo "Done!"