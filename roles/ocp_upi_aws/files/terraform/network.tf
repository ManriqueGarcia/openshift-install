data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_names               = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnet_cidrs    = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 10 + i)]
  private_subnet_cidrs   = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 20 + i)]
  secondary_subnet_cidrs = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 30 + i)]
}

resource "aws_vpc" "ocp_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.ocp_vpc.id
  tags   = { Name = "${var.cluster_name}-igw" }
}

# Subredes públicas
resource "aws_subnet" "public_subnets" {
  count                   = 3
  vpc_id                  = aws_vpc.ocp_vpc.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.az_names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-${local.az_names[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

# EIPs para los NAT Gateways
resource "aws_eip" "nat_eips" {
  count  = 3
  domain = "vpc"
  tags   = { Name = "${var.cluster_name}-eip-${count.index}" }
}

# NAT Gateways (uno en cada subred pública)
resource "aws_nat_gateway" "nat_gws" {
  count         = 3
  allocation_id = aws_eip.nat_eips[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id

  depends_on = [aws_internet_gateway.igw]

  tags = { Name = "${var.cluster_name}-nat-${local.az_names[count.index]}" }
}

# Subredes privadas
resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.ocp_vpc.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.az_names[count.index]

  tags = {
    Name = "${var.cluster_name}-private-${local.az_names[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# Tabla de rutas pública
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.ocp_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.cluster_name}-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Tablas de ruta privadas (una por AZ/NAT GW)
resource "aws_route_table" "private_rts" {
  count  = 3
  vpc_id = aws_vpc.ocp_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gws[count.index].id
  }

  tags = { Name = "${var.cluster_name}-private-rt-${local.az_names[count.index]}" }
}

resource "aws_route_table_association" "private_assoc" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rts[count.index].id
}

# Subredes privadas secundarias (dual-NIC, subred diferente con gateway propio)
resource "aws_subnet" "secondary_private_subnets" {
  count             = var.enable_dual_nic ? 3 : 0
  vpc_id            = aws_vpc.ocp_vpc.id
  cidr_block        = local.secondary_subnet_cidrs[count.index]
  availability_zone = local.az_names[count.index]

  tags = {
    Name = "${var.cluster_name}-secondary-${local.az_names[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_route_table_association" "secondary_private_assoc" {
  count          = var.enable_dual_nic ? 3 : 0
  subnet_id      = aws_subnet.secondary_private_subnets[count.index].id
  route_table_id = aws_route_table.private_rts[count.index].id
}

# VPC Gateway Endpoint para S3 (acceso directo sin pasar por NAT)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.ocp_vpc.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  route_table_ids = concat(
    [aws_route_table.public_rt.id],
    aws_route_table.private_rts[*].id
  )

  tags = { Name = "${var.cluster_name}-s3-endpoint" }
}

output "vpc_id" {
  value = aws_vpc.ocp_vpc.id
}

output "private_subnet_ids" {
  value = aws_subnet.private_subnets[*].id
}

output "nat_gateway_ips" {
  value = aws_eip.nat_eips[*].public_ip
}
