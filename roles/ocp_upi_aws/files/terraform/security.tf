# 1. Security Group para los Masters (Control Plane)
# IMPORTANTE: No usar bloques ingress/egress inline aquí.
# Todas las reglas van como aws_security_group_rule independientes
# para evitar conflictos de estado que borran reglas en cada apply.
resource "aws_security_group" "master_sg" {
  name        = "${var.cluster_name}-master-sg"
  description = "Security group for OpenShift master nodes"
  vpc_id      = aws_vpc.ocp_vpc.id

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

  tags = {
    Name = "${var.cluster_name}-worker-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# --- Reglas del Master SG ---

resource "aws_security_group_rule" "master_ssh" {
  type              = "ingress"
  description       = "SSH"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = length(var.allowed_ssh_cidrs) > 0 ? var.allowed_ssh_cidrs : [aws_vpc.ocp_vpc.cidr_block]
  security_group_id = aws_security_group.master_sg.id
}

resource "aws_security_group_rule" "master_api" {
  type              = "ingress"
  description       = "API Server"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = var.allowed_api_cidrs
  security_group_id = aws_security_group.master_sg.id
}

resource "aws_security_group_rule" "master_mcs" {
  type              = "ingress"
  description       = "Machine Config Server (node join)"
  from_port         = 22623
  to_port           = 22623
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.ocp_vpc.cidr_block]
  security_group_id = aws_security_group.master_sg.id
}

resource "aws_security_group_rule" "master_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.master_sg.id
}

# --- Reglas del Worker SG ---

resource "aws_security_group_rule" "worker_http" {
  type              = "ingress"
  description       = "HTTP Ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker_sg.id
}

resource "aws_security_group_rule" "worker_https" {
  type              = "ingress"
  description       = "HTTPS Ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker_sg.id
}

resource "aws_security_group_rule" "worker_nodeports" {
  type              = "ingress"
  description       = "NodePort (router/default ingress LoadBalancerService)"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker_sg.id
}

resource "aws_security_group_rule" "worker_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker_sg.id
}

# --- Comunicación INTERNA total entre Nodos ---
# Requerido por OVN-Kubernetes SDN: etcd (2379-2380), VXLAN (4789),
# Geneve (6081), kubelet (10250), host-services, y métricas.
# Se usa protocol=-1 (all) porque restringir puertos individuales
# rompe el SDN y causa etcd quorum loss.

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
