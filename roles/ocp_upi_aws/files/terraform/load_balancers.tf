# --- 1. NLB EXTERNO (Para acceso a la API desde fuera) ---
resource "aws_lb" "api_external" {
  name               = "${var.cluster_name}-aext-${random_string.suffix.result}"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.public_subnets[*].id

  tags = { "kubernetes.io/cluster/${var.cluster_name}" = "shared" }
}

resource "aws_lb_target_group" "api_ext_6443" {
  name     = "${var.cluster_name}-aex-${random_string.suffix.result}"
  port     = 6443
  protocol = "TCP"
  vpc_id   = aws_vpc.ocp_vpc.id
  target_type = "ip"
}

resource "aws_lb_listener" "api_ext_6443" {
  load_balancer_arn = aws_lb.api_external.arn
  port              = 6443
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_ext_6443.arn
  }
}

# --- 2. NLB INTERNO (Para comunicación interna del clúster) ---
resource "aws_lb" "api_internal" {
  name               = "${var.cluster_name}-aint-${random_string.suffix.result}"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private_subnets[*].id

  tags = { "kubernetes.io/cluster/${var.cluster_name}" = "shared" }
}

resource "aws_lb_target_group" "api_int_6443" {
  name     = "${var.cluster_name}-ain-${random_string.suffix.result}"
  port     = 6443
  protocol = "TCP"
  vpc_id   = aws_vpc.ocp_vpc.id
  target_type = "ip"
}

# Target Group para Machine Config Server (22623) - VITAL PARA UPI
resource "aws_lb_target_group" "api_int_22623" {
  name     = "${var.cluster_name}-mcs-${random_string.suffix.result}"
  port     = 22623
  protocol = "TCP"
  vpc_id   = aws_vpc.ocp_vpc.id
  target_type = "ip"
}

resource "aws_lb_listener" "api_int_6443" {
  load_balancer_arn = aws_lb.api_internal.arn
  port              = 6443
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_int_6443.arn
  }
}

resource "aws_lb_listener" "api_int_22623" {
  load_balancer_arn = aws_lb.api_internal.arn
  port              = 22623
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_int_22623.arn
  }
}

# --- 3. LB PARA APLICACIONES (Ingress/Router) ---
resource "aws_lb" "ingress" {
  name               = "${var.cluster_name}-ing-${random_string.suffix.result}"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.public_subnets[*].id

  tags = { "kubernetes.io/cluster/${var.cluster_name}" = "shared" }
}

resource "aws_lb_target_group" "ingress_80" {
  name     = "${var.cluster_name}-i80-${random_string.suffix.result}"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.ocp_vpc.id
  target_type = "ip"
}

resource "aws_lb_target_group" "ingress_443" {
  name     = "${var.cluster_name}-i43-${random_string.suffix.result}"
  port     = 443
  protocol = "TCP"
  vpc_id   = aws_vpc.ocp_vpc.id
  target_type = "ip"
}

resource "aws_lb_listener" "ingress_80" {
  load_balancer_arn = aws_lb.ingress.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_80.arn
  }
}

resource "aws_lb_listener" "ingress_443" {
  load_balancer_arn = aws_lb.ingress.arn
  port              = 443
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_443.arn
  }
}
