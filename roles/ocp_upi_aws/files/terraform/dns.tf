# 1. Obtener la Zona Hospedada existente
data "aws_route53_zone" "base_zone" {
  name         = "${var.base_domain}."
  private_zone = false
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

# 4. Registro Comodín (Wildcard) para Aplicaciones (*.apps)
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
