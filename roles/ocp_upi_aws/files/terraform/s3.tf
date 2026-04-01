resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_s3_bucket" "ignition_bucket" {
  bucket        = "ocp-infra-ignition-${var.cluster_name}-${random_string.suffix.result}"
  force_destroy = var.s3_force_destroy

  tags = {
    Name = "${var.cluster_name}-ignition-storage"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ignition_encryption" {
  bucket = aws_s3_bucket.ignition_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ignition_bucket_block" {
  bucket = aws_s3_bucket.ignition_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs desactivadas (comportamiento habitual en buckets nuevos): los PutObject deben ir sin cabecera ACL.
resource "aws_s3_bucket_ownership_controls" "ignition" {
  bucket = aws_s3_bucket.ignition_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [aws_s3_bucket_public_access_block.ignition_bucket_block]
}

resource "aws_s3_object" "bootstrap_ignition" {
  bucket = aws_s3_bucket.ignition_bucket.id
  key    = "bootstrap.ign"
  source = var.bootstrap_ign_path

  depends_on = [
    aws_s3_bucket_server_side_encryption_configuration.ignition_encryption,
    aws_s3_bucket_ownership_controls.ignition,
  ]
}

resource "aws_s3_object" "master_ignition" {
  bucket = aws_s3_bucket.ignition_bucket.id
  key    = "master.ign"
  source = var.master_ign_path

  depends_on = [
    aws_s3_bucket_server_side_encryption_configuration.ignition_encryption,
    aws_s3_bucket_ownership_controls.ignition,
  ]
}

resource "aws_s3_object" "worker_ignition" {
  bucket = aws_s3_bucket.ignition_bucket.id
  key    = "worker.ign"
  source = var.worker_ign_path

  depends_on = [
    aws_s3_bucket_server_side_encryption_configuration.ignition_encryption,
    aws_s3_bucket_ownership_controls.ignition,
  ]
}

output "ignition_bucket_id" {
  value = aws_s3_bucket.ignition_bucket.id
}
