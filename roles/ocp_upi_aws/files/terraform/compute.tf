locals {
  ignition_version = "3.2.0"
}

# --- 1. NODO BOOTSTRAP (subred pública para acceso SSH directo) ---
resource "aws_instance" "bootstrap" {
  ami                         = var.rhcos_ami
  instance_type               = var.bootstrap_instance_type
  iam_instance_profile        = aws_iam_instance_profile.master_profile.name
  subnet_id                   = aws_subnet.public_subnets[0].id
  vpc_security_group_ids      = [aws_security_group.master_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = var.root_volume_type
    encrypted   = true
  }

  user_data = jsonencode({
    ignition = {
      version = local.ignition_version
      config = {
        replace = {
          source = "s3://${aws_s3_bucket.ignition_bucket.id}/bootstrap.ign"
        }
      }
    }
  })

  tags = {
    Name = "${var.cluster_name}-bootstrap"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  lifecycle {
    ignore_changes = [user_data, ami]
  }

  depends_on = [
    aws_route_table_association.public_assoc,
    aws_vpc_endpoint.s3
  ]
}

# --- 2. NODOS MASTER (3 nodos para Alta Disponibilidad) ---
resource "aws_instance" "master" {
  count                  = var.master_count
  ami                    = var.rhcos_ami
  instance_type          = var.master_instance_type
  iam_instance_profile   = aws_iam_instance_profile.master_profile.name
  subnet_id              = aws_subnet.private_subnets[count.index].id
  vpc_security_group_ids = [aws_security_group.master_sg.id]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = var.root_volume_type
    encrypted   = true
  }

  user_data = jsonencode({
    ignition = {
      version = local.ignition_version
      config = {
        replace = {
          source = "s3://${aws_s3_bucket.ignition_bucket.id}/master.ign"
        }
      }
    }
  })

  tags = {
    Name = "${var.cluster_name}-master-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  lifecycle {
    ignore_changes = [user_data, ami]
  }

  depends_on = [
    aws_route_table_association.private_assoc,
    aws_vpc_endpoint.s3,
    aws_lb.api_internal
  ]
}

# --- 3. NODOS WORKER ---
resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = var.rhcos_ami
  instance_type          = var.worker_instance_type
  iam_instance_profile   = aws_iam_instance_profile.worker_profile.name
  subnet_id              = aws_subnet.private_subnets[count.index].id
  vpc_security_group_ids = [aws_security_group.worker_sg.id]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = var.root_volume_type
    encrypted   = true
  }

  user_data = jsonencode({
    ignition = {
      version = local.ignition_version
      config = {
        replace = {
          source = "s3://${aws_s3_bucket.ignition_bucket.id}/worker.ign"
        }
      }
    }
  })

  tags = {
    Name = "${var.cluster_name}-worker-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  lifecycle {
    ignore_changes = [user_data, ami]
  }

  depends_on = [
    aws_route_table_association.private_assoc,
    aws_vpc_endpoint.s3,
    aws_lb.api_internal
  ]
}

# --- 4. SEGUNDO ENI (dual-NIC) ---
resource "aws_network_interface" "master_secondary" {
  count           = var.enable_dual_nic ? var.master_count : 0
  subnet_id       = aws_subnet.secondary_private_subnets[count.index].id
  security_groups = [aws_security_group.master_sg.id]

  tags = {
    Name = "${var.cluster_name}-master-${count.index}-ens6"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_network_interface_attachment" "master_secondary" {
  count                = var.enable_dual_nic ? var.master_count : 0
  instance_id          = aws_instance.master[count.index].id
  network_interface_id = aws_network_interface.master_secondary[count.index].id
  device_index         = 1
}

resource "aws_network_interface" "worker_secondary" {
  count           = var.enable_dual_nic ? var.worker_count : 0
  subnet_id       = aws_subnet.secondary_private_subnets[count.index].id
  security_groups = [aws_security_group.worker_sg.id]

  tags = {
    Name = "${var.cluster_name}-worker-${count.index}-ens6"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_network_interface_attachment" "worker_secondary" {
  count                = var.enable_dual_nic ? var.worker_count : 0
  instance_id          = aws_instance.worker[count.index].id
  network_interface_id = aws_network_interface.worker_secondary[count.index].id
  device_index         = 1
}

# Registrar Workers en el Target Group del Ingress (Router)
resource "aws_lb_target_group_attachment" "worker_ingress_80" {
  count            = var.worker_count
  target_group_arn = aws_lb_target_group.ingress_80.arn
  target_id        = aws_instance.worker[count.index].private_ip
}

resource "aws_lb_target_group_attachment" "worker_ingress_443" {
  count            = var.worker_count
  target_group_arn = aws_lb_target_group.ingress_443.arn
  target_id        = aws_instance.worker[count.index].private_ip
}

# Registrar Bootstrap en los Target Groups de la API
resource "aws_lb_target_group_attachment" "bootstrap_api_ext" {
  target_group_arn = aws_lb_target_group.api_ext_6443.arn
  target_id        = aws_instance.bootstrap.private_ip
}

resource "aws_lb_target_group_attachment" "bootstrap_api_int" {
  target_group_arn = aws_lb_target_group.api_int_6443.arn
  target_id        = aws_instance.bootstrap.private_ip
}

resource "aws_lb_target_group_attachment" "bootstrap_mcs" {
  target_group_arn = aws_lb_target_group.api_int_22623.arn
  target_id        = aws_instance.bootstrap.private_ip
}

# Registrar Masters en los Target Groups de la API
resource "aws_lb_target_group_attachment" "master_api_ext" {
  count            = var.master_count
  target_group_arn = aws_lb_target_group.api_ext_6443.arn
  target_id        = aws_instance.master[count.index].private_ip
}

resource "aws_lb_target_group_attachment" "master_api_int" {
  count            = var.master_count
  target_group_arn = aws_lb_target_group.api_int_6443.arn
  target_id        = aws_instance.master[count.index].private_ip
}

resource "aws_lb_target_group_attachment" "master_mcs" {
  count            = var.master_count
  target_group_arn = aws_lb_target_group.api_int_22623.arn
  target_id        = aws_instance.master[count.index].private_ip
}
