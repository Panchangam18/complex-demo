output "transit_gateway_id" {
  description = "EC2 Transit Gateway identifier"
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  description = "EC2 Transit Gateway ARN"
  value       = aws_ec2_transit_gateway.this.arn
}

output "transit_gateway_association_default_route_table_id" {
  description = "EC2 Transit Gateway association default route table identifier"
  value       = aws_ec2_transit_gateway.this.association_default_route_table_id
}

output "transit_gateway_propagation_default_route_table_id" {
  description = "EC2 Transit Gateway propagation default route table identifier"
  value       = aws_ec2_transit_gateway.this.propagation_default_route_table_id
}

output "transit_gateway_route_table_id" {
  description = "EC2 Transit Gateway route table identifier"
  value       = aws_ec2_transit_gateway_route_table.this.id
}

output "vpc_attachment_ids" {
  description = "Map of VPC attachment IDs"
  value       = { for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id }
}

output "peering_attachment_ids" {
  description = "Map of peering attachment IDs"
  value       = { for k, v in aws_ec2_transit_gateway_peering_attachment.this : k => v.id }
}

output "ram_resource_share_id" {
  description = "The ID of the RAM resource share"
  value       = var.ram_share_enabled ? aws_ram_resource_share.this[0].id : null
}