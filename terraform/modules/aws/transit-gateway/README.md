# AWS Transit Gateway Module

This module creates an AWS Transit Gateway for connecting multiple VPCs and on-premises networks.

## Features

- Transit Gateway with customizable ASN
- VPC attachments with route table associations and propagations
- Static routes configuration
- Cross-region peering support
- Resource Access Manager (RAM) sharing
- DNS support for attached VPCs

## Usage

```hcl
module "transit_gateway" {
  source = "../../../modules/aws/transit-gateway"

  name        = "main-tgw"
  environment = "prod"
  description = "Main Transit Gateway for production environment"
  
  amazon_side_asn = 64512
  enable_dns_support = true
  enable_dns_hostnames = true
  
  # VPC Attachments
  vpc_attachments = {
    vpc1 = {
      vpc_id     = module.vpc1.vpc_id
      subnet_ids = module.vpc1.private_subnets
      tags = {
        Purpose = "Application VPC"
      }
    }
    vpc2 = {
      vpc_id     = module.vpc2.vpc_id
      subnet_ids = module.vpc2.private_subnets
      tags = {
        Purpose = "Database VPC"
      }
    }
  }
  
  # Static Routes
  transit_gateway_routes = {
    on_premises = {
      destination_cidr_block = "192.168.0.0/16"
      attachment_id          = "tgw-attach-xxxxxx"  # VPN attachment
    }
  }
  
  # Cross-Region Peering
  enable_cross_region_peering = true
  peering_attachments = {
    us_west_2 = {
      peer_region             = "us-west-2"
      peer_transit_gateway_id = "tgw-xxxxxxxxx"
    }
  }
  
  # RAM Sharing (for multi-account)
  ram_share_enabled = true
  ram_principals = [
    "123456789012",  # Account ID
    "arn:aws:organizations::123456789012:ou/o-xxxxxxxxxx/ou-xxxx-xxxxxxxx"  # OU
  ]
  
  tags = {
    Terraform   = "true"
    Environment = "prod"
  }
}
```

## Adding Routes to VPC Route Tables

After creating the Transit Gateway, you need to add routes in your VPC route tables:

```hcl
resource "aws_route" "tgw_route" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = module.transit_gateway.transit_gateway_id
}
```

## Outputs

- `transit_gateway_id` - The Transit Gateway ID
- `transit_gateway_arn` - The Transit Gateway ARN
- `transit_gateway_route_table_id` - The Transit Gateway route table ID
- `vpc_attachment_ids` - Map of VPC attachment IDs
- `peering_attachment_ids` - Map of peering attachment IDs