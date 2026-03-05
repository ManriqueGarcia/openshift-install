data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_names = slice(data.aws_availability_zones.available.names, 0,3)
}

resource "aws_vpc" "ocp_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.ocp_vpc.id
  tags   = { Name = "${var.cluster_name}-igw" }
}



#Subredes públicas
resource "aws_subnet" "public_subnets" {
  count			  = 3
  vpc_id 		  = aws_vpc.ocp_vpc.id
  cidr_block		  = "10.0.${10 + count.index}.0/24"
  availability_zone 	  = local.az_names[count.index]
  map_public_ip_on_launch = true
 
  tags = {
    Name = "${var.cluster_name}-public-${local.az_names[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"		= "1" # Tag para que OCP sepa donde poner LBs publicos
  }
}

#EIPs para los NAT Gateways
resource "aws_eip" "nat_eips" {
  count = "3"
  domain = "vpc"
  tags  = { Name = "${var.cluster_name}-eip-${count.index}" }
}

# NAT Gateways (uno en cada subred publica)
resource "aws_nat_gateway" "nat_gws" {
  count		= 3
  allocation_id = aws_eip.nat_eips[count.index].id
  subnet_id	= aws_subnet.public_subnets[count.index].id

  tags = { Name = "${var.cluster_name}-nat-${local.az_names[count.index]}"  }
}

# Subredes privadas

resource "aws_subnet" "private_subnets" {
  count		    = "3"
  vpc_id	    = aws_vpc.ocp_vpc.id
  cidr_block	    = "10.0.${20 + count.index}.0/24"
  availability_zone = local.az_names[count.index]

  tags = {
    Name = "${var.cluster_name}-private-${local.az_names[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"   = "1" # Tag para LBs internos
  }
}

# Tabla de rutas públicas

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.ocp_vpc.id
  route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  count = 3
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Tablas de ruta privadas. tiene que haber una por cada NAT GW

resource "aws_route_table" "private_rts" {
  count = 3
  vpc_id = aws_vpc.ocp_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gws[count.index].id
  }
}

resource "aws_route_table_association" "private_assoc" {
  count = 3
  subnet_id = aws_subnet.private_subnets[count.index].id
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

