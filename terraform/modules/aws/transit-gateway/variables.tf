variable "name" {
  description = "Name to be used on all resources as prefix"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "description" {
  description = "Description of the Transit Gateway"
  type        = string
  default     = ""
}

variable "amazon_side_asn" {
  description = "Private Autonomous System Number (ASN) for the Amazon side of a BGP session"
  type        = number
  default     = 64512
}

variable "enable_dns_support" {
  description = "Whether DNS support is enabled"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Whether DNS hostnames are enabled"
  type        = bool
  default     = true
}

variable "enable_multicast_support" {
  description = "Whether multicast support is enabled"
  type        = bool
  default     = false
}

variable "enable_default_route_table_association" {
  description = "Whether resource attachments are automatically associated with the default association route table"
  type        = bool
  default     = true
}

variable "enable_default_route_table_propagation" {
  description = "Whether resource attachments automatically propagate routes to the default propagation route table"
  type        = bool
  default     = true
}

variable "vpc_attachments" {
  description = "Map of VPC attachments"
  type = map(object({
    vpc_id                                          = string
    subnet_ids                                      = list(string)
    dns_support                                     = optional(bool, true)
    ipv6_support                                    = optional(bool, false)
    transit_gateway_default_route_table_association = optional(bool, true)
    transit_gateway_default_route_table_propagation = optional(bool, true)
    tags                                            = optional(map(string), {})
  }))
  default = {}
}

variable "transit_gateway_routes" {
  description = "Map of transit gateway routes"
  type = map(object({
    destination_cidr_block = string
    attachment_id          = string
    blackhole              = optional(bool, false)
  }))
  default = {}
}

variable "enable_cross_region_peering" {
  description = "Whether to create cross-region peering attachments"
  type        = bool
  default     = false
}

variable "peering_attachments" {
  description = "Map of cross-region peering attachments"
  type = map(object({
    peer_region          = string
    peer_transit_gateway_id = string
    tags                 = optional(map(string), {})
  }))
  default = {}
}

variable "ram_share_enabled" {
  description = "Whether to enable sharing the Transit Gateway using Resource Access Manager (RAM)"
  type        = bool
  default     = false
}

variable "ram_principals" {
  description = "List of principals to share the Transit Gateway with"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}