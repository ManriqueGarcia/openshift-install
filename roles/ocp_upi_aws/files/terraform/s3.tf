#  1. Crear el Bucket de S3
resource "aws_s3_bucket" "ignition_bucket" {
  bucket = "ocp-infra-ignition-${var.cluster_name}-${random_string.suffix.result}"
  
  # Fuerza el borrado del bucket aunque tenga archivos al hacer destroy
  force_destroy = true 

  tags = {
    Name = "${var.cluster_name}-ignition-storage"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# 2. Generar un sufijo aleatorio para que el nombre del bucket sea único
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# 3. Bloquear acceso público (Seguridad ante todo)
resource "aws_s3_bucket_public_access_block" "ignition_bucket_block" {
  bucket = aws_s3_bucket.ignition_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#  4. (Opcional) Si ya tienes los archivos generados, podrías subirlos así:
 resource "aws_s3_object" "bootstrap_ignition" {
   bucket = aws_s3_bucket.ignition_bucket.id
   key    = "bootstrap.ign"
   source = var.bootstrap_ign_path
 }

 resource "aws_s3_object" "master_ignition" {
   bucket = aws_s3_bucket.ignition_bucket.id
   key    = "master.ign"
   source = var.master_ign_path
 }

 resource "aws_s3_object" "worker_ignition" {
   bucket = aws_s3_bucket.ignition_bucket.id
   key    = "worker.ign"
   source = var.worker_ign_path
 }

 output "ignition_bucket_id" {
     value = aws_s3_bucket.ignition_bucket.id
   }
