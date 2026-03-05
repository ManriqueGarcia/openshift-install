# 1. Security Group para los Masters (Control Plane)
resource "aws_security_group" "master_sg" {
  name        = "${var.cluster_name}-master-sg"
  description = "Security group for OpenShift master nodes"
  vpc_id      = aws_vpc.ocp_vpc.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Machine Config Server (necesario para nodos que se unen)
  ingress {
    from_port   = 22623
    to_port     = 22623
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.ocp_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-master-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# 2. Security Group para los Workers (Infra/App)
resource "aws_security_group" "worker_sg" {
  name        = "${var.cluster_name}-worker-sg"
  description = "Security group for OpenShift worker nodes"
  vpc_id      = aws_vpc.ocp_vpc.id

  # Tráfico HTTP/HTTPS para el Router/Ingress
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-worker-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# 3. Comunicación INTERNA total entre Nodos
# Esto es vital para SDN (Software Defined Network) de OpenShift
resource "aws_security_group_rule" "internal_master_to_master" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.master_sg.id
  security_group_id        = aws_security_group.master_sg.id
}

resource "aws_security_group_rule" "internal_worker_to_master" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.worker_sg.id
  security_group_id        = aws_security_group.master_sg.id
}

resource "aws_security_group_rule" "internal_master_to_worker" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.master_sg.id
  security_group_id        = aws_security_group.worker_sg.id
}

resource "aws_security_group_rule" "internal_worker_to_worker" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.worker_sg.id
  security_group_id        = aws_security_group.worker_sg.id
}
