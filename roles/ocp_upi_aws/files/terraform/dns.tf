# 1. Obtener la Zona Hospedada existente (publica)
data "aws_route53_zone" "base_zone" {
  name         = "${var.base_domain}."
  private_zone = false
}

# 1b. Zona privada para DNS interno del cluster
resource "aws_route53_zone" "private_zone" {
  name = "${var.cluster_name}.${var.base_domain}"

  vpc {
    vpc_id = aws_vpc.ocp_vpc.id
  }

  tags = {
    Name                                     = "${var.infra_id}-int"
    "kubernetes.io/cluster/${var.infra_id}"   = "owned"
  }
}

# 1c. Registro api-int en zona privada
resource "aws_route53_record" "api_internal_private" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "api-int.${var.cluster_name}.${var.base_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.api_internal.dns_name
    zone_id                = aws_lb.api_internal.zone_id
    evaluate_target_health = true
  }
}

# 1d. Registro api en zona privada
resource "aws_route53_record" "api_private" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "api.${var.cluster_name}.${var.base_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.api_internal.dns_name
    zone_id                = aws_lb.api_internal.zone_id
    evaluate_target_health = true
  }
}

# 2. Registro para API Externa
resource "aws_route53_record" "api_external" {
  zone_id = data.aws_route53_zone.base_zone.zone_id
  name    = "api.${var.cluster_name}.${data.aws_route53_zone.base_zone.name}"
  type    = "A"

  alias {
    name                   = aws_lb.api_external.dns_name
    zone_id                = aws_lb.api_external.zone_id
    evaluate_target_health = true
  }
}

# 3. Registro para API Interna (api-int)
resource "aws_route53_record" "api_internal" {
  zone_id = data.aws_route53_zone.base_zone.zone_id
  name    = "api-int.${var.cluster_name}.${data.aws_route53_zone.base_zone.name}"
  type    = "A"

  alias {
    name                   = aws_lb.api_internal.dns_name
    zone_id                = aws_lb.api_internal.zone_id
    evaluate_target_health = true
  }
}

# *.apps: alias al NLB de ingress (NodePortService en el clúster). Sin LoadBalancerService del operador = sin Route53 minteado en la zona privada.
resource "aws_route53_record" "apps_wildcard" {
  zone_id = data.aws_route53_zone.base_zone.zone_id
  name    = "*.apps.${var.cluster_name}.${data.aws_route53_zone.base_zone.name}"
  type    = "A"

  alias {
    name                   = aws_lb.ingress.dns_name
    zone_id                = aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "apps_wildcard_private" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "*.apps.${var.cluster_name}.${var.base_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ingress.dns_name
    zone_id                = aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}
