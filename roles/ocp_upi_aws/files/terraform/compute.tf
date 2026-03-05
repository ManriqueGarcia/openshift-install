# --- 1. NODO BOOTSTRAP (Se crea en la subred pública para que sea accesible) ---
resource "aws_instance" "bootstrap" {
  ami                         = var.rhcos_ami
  instance_type               = "m5.2xlarge"
  iam_instance_profile        = aws_iam_instance_profile.master_profile.name
  subnet_id                   = aws_subnet.public_subnets[0].id
  vpc_security_group_ids      = [aws_security_group.master_sg.id]
  associate_public_ip_address = true 

  root_block_device {
    volume_size = 120
    volume_type = "gp3"
  }

  user_data = jsonencode({
    ignition = {
      version = "3.2.0"
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

  depends_on = [
    aws_route_table_association.public_assoc,
    aws_vpc_endpoint.s3
  ]
}

# --- 2. NODOS MASTER (3 nodos para Alta Disponibilidad) ---
resource "aws_instance" "master" {
  count                       = 3
  ami                         = var.rhcos_ami
  instance_type               = "m5.2xlarge"
  iam_instance_profile        = aws_iam_instance_profile.master_profile.name
  subnet_id                   = aws_subnet.private_subnets[count.index].id
  vpc_security_group_ids      = [aws_security_group.master_sg.id]

  root_block_device {
    volume_size = 120
    volume_type = "gp3"
  }

  user_data = jsonencode({
    ignition = {
      version = "3.2.0"
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

  depends_on = [
    aws_route_table_association.private_assoc,
    aws_vpc_endpoint.s3,
    aws_lb.api_internal
  ]
}

# --- 3. NODOS WORKER (2 o 3) ---
resource "aws_instance" "worker" {
  count                       = 3
  ami                         = var.rhcos_ami
  instance_type               = "m5.large"
  iam_instance_profile        = aws_iam_instance_profile.worker_profile.name
  subnet_id                   = aws_subnet.private_subnets[count.index].id
  vpc_security_group_ids      = [aws_security_group.worker_sg.id]

  root_block_device {
    volume_size = 120
    volume_type = "gp3"
  }

  user_data = jsonencode({
    ignition = {
      version = "3.2.0"
      config = {
        replace = {
          source = "s3://${aws_s3_bucket.ignition_bucket.id}/worker.ign"
        }
      }
    }
  })

  tags = { 
    Name = "${var.cluster_name}-worker-${count.index}", 
    "kubernetes.io/cluster/${var.cluster_name}" = "shared" 
  }

  depends_on = [
    aws_route_table_association.private_assoc,
    aws_vpc_endpoint.s3,
    aws_lb.api_internal
  ]
}

# Registrar Workers en el Target Group del Ingress (Router)
resource "aws_lb_target_group_attachment" "worker_ingress_80" {
  count            = 3
  target_group_arn = aws_lb_target_group.ingress_80.arn
  target_id        = aws_instance.worker[count.index].private_ip
}

resource "aws_lb_target_group_attachment" "worker_ingress_443" {
  count            = 3
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
  count            = 3
  target_group_arn = aws_lb_target_group.api_ext_6443.arn
  target_id        = aws_instance.master[count.index].private_ip
}

resource "aws_lb_target_group_attachment" "master_api_int" {
  count            = 3
  target_group_arn = aws_lb_target_group.api_int_6443.arn
  target_id        = aws_instance.master[count.index].private_ip
}

resource "aws_lb_target_group_attachment" "master_mcs" {
  count            = 3
  target_group_arn = aws_lb_target_group.api_int_22623.arn
  target_id        = aws_instance.master[count.index].private_ip
}
