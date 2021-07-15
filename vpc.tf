########################################
## Input Variables
########################################
variable "vpc_cidr" {
  description = "Network CIDR for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_mask" {
  description = "Number of bits for netmask to use with subnets"
  type        = number
  default     = 23
}

variable "num_subnets_public" {
  description = "Number of public subnets to create (minimum 2 for load balancers)"
  type        = number
  default     = 2
}

variable "num_subnets_private" {
  description = "Number of public subnets to create (minimum 2 for load balancers)"
  type        = number
  default     = 2
}

variable "num_zones" {
  description = "Number of availability zones to use within the region"
  type        = number
  default     = 2
}


########################################
## Data lookups and Locals
########################################
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Extract network specifics from the input variables
  vpc_netmask = split("/", var.vpc_cidr)[1]
  newbits     = var.subnet_mask - local.vpc_netmask

  # We're only supporting private a public subnets, so alternate
  #   public and private. By pre-defining the even subnets as
  #   public and private subnets by private, we avoid potentially
  #   changing already established subnets out from under us causing
  #   large numbers of resources to be destroyed and rebuilt.
  nat_subnet = aws_subnet.public[cidrsubnet(var.vpc_cidr, local.newbits, 0)]
  subnets_public = {
    for index in range(0, var.num_subnets_public) :
    cidrsubnet(var.vpc_cidr, local.newbits, 2 * index) => element(local.zones, index)
  }

  subnets_private = {
    for index in range(0, var.num_subnets_private) :
    cidrsubnet(var.vpc_cidr, local.newbits, 2 * index + 1) => element(local.zones, index)
  }

  # Ensure we have a consistent list of AZ's by
  #   turning the set of az names into a sorted list
  #   and slicing that list into one that matches the number
  #   of expected availability zones.
  zones_sorted = sort(data.aws_availability_zones.available.names)
  zones        = slice(local.zones_sorted, 0, var.num_zones)
}



########################################
## Network Setup
########################################
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = var.tags.Application
  }
}

resource "aws_subnet" "public" {
  for_each = local.subnets_public

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.key
  availability_zone       = each.value
  map_public_ip_on_launch = true

  tags = {
    Name = "public - ${each.key}"
  }
}

resource "aws_subnet" "private" {
  for_each = local.subnets_private

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.key
  availability_zone       = each.value
  map_public_ip_on_launch = false

  tags = {
    Name = "private - ${each.key}"
  }
}


########################################
## Network Gateways
########################################
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = var.tags.Application
  }
}

# NAT gateways are expensive, so I'm just using one. Typically, I would
#   create one per availability zone.
resource "aws_eip" "nat" {
  vpc        = true
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = local.nat_subnet.id

  tags = {
    Name = "NAT ${var.tags.Application} - ${local.nat_subnet.availability_zone}"
  }
}


########################################
## Routing
########################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # In more complex setups, routes should be definied
  # separately from the route table.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Normally there would be one route table per NAT gateway (ie. 1 per AZ)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
