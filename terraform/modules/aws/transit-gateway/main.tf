locals {
  description = var.description != "" ? var.description : "Transit Gateway for ${var.environment}"
}

################################################################################
# Transit Gateway
################################################################################

resource "aws_ec2_transit_gateway" "this" {
  description                     = local.description
  amazon_side_asn                 = var.amazon_side_asn
  dns_support                     = var.enable_dns_support ? "enable" : "disable"
  vpn_ecmp_support                = "enable"
  default_route_table_association = var.enable_default_route_table_association ? "enable" : "disable"
  default_route_table_propagation = var.enable_default_route_table_propagation ? "enable" : "disable"
  multicast_support               = var.enable_multicast_support ? "enable" : "disable"

  tags = merge(
    var.tags,
    {
      Name        = var.name
      Environment = var.environment
    }
  )
}

################################################################################
# Transit Gateway Route Tables
################################################################################

resource "aws_ec2_transit_gateway_route_table" "this" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-rtb"
      Environment = var.environment
    }
  )
}

################################################################################
# VPC Attachments
################################################################################

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.vpc_attachments

  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = each.value.vpc_id
  subnet_ids                                      = each.value.subnet_ids
  dns_support                                     = each.value.dns_support ? "enable" : "disable"
  ipv6_support                                    = each.value.ipv6_support ? "enable" : "disable"
  transit_gateway_default_route_table_association = each.value.transit_gateway_default_route_table_association
  transit_gateway_default_route_table_propagation = each.value.transit_gateway_default_route_table_propagation

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name        = "${var.name}-${each.key}-attachment"
      Environment = var.environment
    }
  )
}

################################################################################
# Transit Gateway Routes
################################################################################

resource "aws_ec2_transit_gateway_route" "this" {
  for_each = var.transit_gateway_routes

  destination_cidr_block         = each.value.destination_cidr_block
  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
  blackhole                      = each.value.blackhole
}

################################################################################
# Route Table Associations
################################################################################

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = var.vpc_attachments

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}

################################################################################
# Route Table Propagations
################################################################################

resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each = var.vpc_attachments

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}

################################################################################
# Cross-Region Peering Attachments
################################################################################

resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  for_each = var.enable_cross_region_peering ? var.peering_attachments : {}

  transit_gateway_id      = aws_ec2_transit_gateway.this.id
  peer_region             = each.value.peer_region
  peer_transit_gateway_id = each.value.peer_transit_gateway_id

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name        = "${var.name}-${each.key}-peering"
      Environment = var.environment
    }
  )
}

# Accepter side configuration (needs to be run in peer region)
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "this" {
  for_each = var.enable_cross_region_peering ? var.peering_attachments : {}

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.this[each.key].id

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-${each.key}-peering-accepter"
      Environment = var.environment
    }
  )
}

################################################################################
# Resource Access Manager (RAM) Share
################################################################################

resource "aws_ram_resource_share" "this" {
  count = var.ram_share_enabled ? 1 : 0

  name                      = "${var.name}-share"
  allow_external_principals = false

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-share"
      Environment = var.environment
    }
  )
}

resource "aws_ram_resource_association" "this" {
  count = var.ram_share_enabled ? 1 : 0

  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.this[0].arn
}

resource "aws_ram_principal_association" "this" {
  for_each = var.ram_share_enabled ? toset(var.ram_principals) : []

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.this[0].arn
}