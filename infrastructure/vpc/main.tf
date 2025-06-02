data "aws_availability_zones" "available" {}

locals {
  selected_azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

resource "aws_vpc" "main_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.name_prefix}-vpc"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name        = "${var.name_prefix}-igw"
    Environment = var.environment
  }
}

resource "aws_eip" "nat_eip" {
  count = 1
  domain = "vpc"

  tags = {
    Name        = "${var.name_prefix}-eip"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_subnets" {
  for_each = toset(local.selected_azs)

  vpc_id                  = aws_vpc.main_vpc.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, index(local.selected_azs, each.key))
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.name_prefix}-${each.key}-public"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_subnets" {
  for_each = toset(local.selected_azs)

  vpc_id            = aws_vpc.main_vpc.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 100 + index(local.selected_azs, each.key))

  tags = {
    Name        = "${var.name_prefix}-${each.key}-private"
    Environment = var.environment
    "karpenter.sh/discovery"  = "${var.name_prefix}-eks"
  }
}

resource "aws_nat_gateway" "main_nat_gw" {
  allocation_id = aws_eip.nat_eip[0].id
  subnet_id     = aws_subnet.public_subnets[local.selected_azs[0]].id

  tags = {
    Name        = "${var.name_prefix}-nat"
    Environment = var.environment
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name        = "${var.name_prefix}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main_nat_gw.id
  }

  tags = {
    Name        = "${var.name_prefix}-private-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public_assoc" {
  for_each = aws_subnet.public_subnets

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_assoc" {
  for_each = aws_subnet.private_subnets

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rt.id
}
