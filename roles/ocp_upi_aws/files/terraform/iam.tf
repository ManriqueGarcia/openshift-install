# 1. Política de Confianza (Permite que las EC2 asuman el rol)
data "aws_iam_policy_document" "ec2_trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# --- ROL PARA MASTERS ---
resource "aws_iam_role" "master_role" {
  name               = "${var.cluster_name}-master-role-${random_string.suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust_policy.json
  tags               = { "kubernetes.io/cluster/${var.cluster_name}" = "shared" }
}

resource "aws_iam_instance_profile" "master_profile" {
  name = "${var.cluster_name}-master-profile-${random_string.suffix.result}"
  role = aws_iam_role.master_role.name
}

# --- ROL PARA WORKERS ---
resource "aws_iam_role" "worker_role" {
  name               = "${var.cluster_name}-worker-role-${random_string.suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust_policy.json
  tags               = { "kubernetes.io/cluster/${var.cluster_name}" = "shared" }
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.cluster_name}-worker-profile-${random_string.suffix.result}"
  role = aws_iam_role.worker_role.name
}

# --- PERMISOS PARA S3 (Lectura de Ignition) ---
resource "aws_iam_policy" "s3_reader_policy" {
  name        = "${var.cluster_name}-s3-reader-policy-${random_string.suffix.result}"
  description = "Permite a los nodos leer los archivos de ignition del bucket S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.ignition_bucket.arn,
          "${aws_s3_bucket.ignition_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Adjuntar la política de S3 a ambos roles
resource "aws_iam_role_policy_attachment" "master_s3_attach" {
  role       = aws_iam_role.master_role.name
  policy_arn = aws_iam_policy.s3_reader_policy.arn
}

resource "aws_iam_role_policy_attachment" "worker_s3_attach" {
  role       = aws_iam_role.worker_role.name
  policy_arn = aws_iam_policy.s3_reader_policy.arn
}

# Adjuntar permisos de SSM a los Masters
resource "aws_iam_role_policy_attachment" "master_ssm" {
  role       = aws_iam_role.master_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Adjuntar permisos de SSM a los Workers
resource "aws_iam_role_policy_attachment" "worker_ssm" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# --- PERMISOS PARA CLOUD CONTROLLER MANAGER (Masters) ---
resource "aws_iam_policy" "master_cloud_provider" {
  name        = "${var.cluster_name}-master-cloud-${random_string.suffix.result}"
  description = "Permisos para el Cloud Controller Manager en los masters"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeVpcs",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:CreateVolume",
          "ec2:DeleteVolume"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:AttachLoadBalancerToSubnets",
          "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancerPolicy",
          "elasticloadbalancing:CreateLoadBalancerListeners",
          "elasticloadbalancing:ConfigureHealthCheck",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancerListeners",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DetachLoadBalancerFromSubnets",
          "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
          "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:SetLoadBalancerPoliciesOfListener"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "master_cloud_provider" {
  role       = aws_iam_role.master_role.name
  policy_arn = aws_iam_policy.master_cloud_provider.arn
}

# --- PERMISOS EC2 BASICOS PARA WORKERS ---
resource "aws_iam_policy" "worker_cloud_provider" {
  name        = "${var.cluster_name}-worker-cloud-${random_string.suffix.result}"
  description = "Permisos EC2 basicos para los workers"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeVpcs",
          "ec2:DescribeAvailabilityZones"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker_cloud_provider" {
  role       = aws_iam_role.worker_role.name
  policy_arn = aws_iam_policy.worker_cloud_provider.arn
}
