# --- 1. NLB EXTERNO (acceso a la API desde fuera) ---
resource "aws_lb" "api_external" {
  name               = "${var.cluster_name}-aext-${random_string.suffix.result}"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name = "${var.cluster_name}-api-external"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_lb_target_group" "api_ext_6443" {
  name        = "${var.cluster_name}-aex-${random_string.suffix.result}"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = aws_vpc.ocp_vpc.id
  target_type = "ip"

  tags = { Name = "${var.cluster_name}-api-ext-6443" }
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

# --- 2. NLB INTERNO (comunicación interna del clúster) ---
resource "aws_lb" "api_internal" {
  name               = "${var.cluster_name}-aint-${random_string.suffix.result}"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private_subnets[*].id

  tags = {
    Name = "${var.cluster_name}-api-internal"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_lb_target_group" "api_int_6443" {
  name        = "${var.cluster_name}-ain-${random_string.suffix.result}"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = aws_vpc.ocp_vpc.id
  target_type = "ip"

  tags = { Name = "${var.cluster_name}-api-int-6443" }
}

resource "aws_lb_target_group" "api_int_22623" {
  name        = "${var.cluster_name}-mcs-${random_string.suffix.result}"
  port        = 22623
  protocol    = "TCP"
  vpc_id      = aws_vpc.ocp_vpc.id
  target_type = "ip"

  tags = { Name = "${var.cluster_name}-mcs-22623" }
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

# --- 3. NLB aplicaciones (UPI): IngressController con NodePortService; NLB :80/:443 -> NodePorts en workers ---
resource "aws_lb" "ingress" {
  name               = "${var.cluster_name}-ing-${random_string.suffix.result}"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name = "${var.cluster_name}-ingress"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_lb_target_group" "ingress_http_np" {
  name        = "${var.cluster_name}-inh-${random_string.suffix.result}"
  port        = var.ingress_nodeport_http
  protocol    = "TCP"
  vpc_id      = aws_vpc.ocp_vpc.id
  target_type = "ip"

  tags = { Name = "${var.cluster_name}-ingress-nodeport-http" }
}

resource "aws_lb_target_group" "ingress_https_np" {
  name        = "${var.cluster_name}-ins-${random_string.suffix.result}"
  port        = var.ingress_nodeport_https
  protocol    = "TCP"
  vpc_id      = aws_vpc.ocp_vpc.id
  target_type = "ip"

  tags = { Name = "${var.cluster_name}-ingress-nodeport-https" }
}

resource "aws_lb_listener" "ingress_80" {
  load_balancer_arn = aws_lb.ingress.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_http_np.arn
  }
}

resource "aws_lb_listener" "ingress_443" {
  load_balancer_arn = aws_lb.ingress.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_https_np.arn
  }
}
