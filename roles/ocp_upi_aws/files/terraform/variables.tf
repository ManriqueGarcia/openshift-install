variable "aws_region"         { default = "eu-west-1" }
variable "cluster_name"      { default = "test-cluster" }
variable "base_domain"       { default = "example.com" }
variable "vpc_cidr"          { default = "10.0.0.0/16" }
variable "rhcos_ami"         { default = "ami-0ce416143802f719b" }
variable "bootstrap_ign_path" { default = "../ocp/bootstrap.ign" }
variable "master_ign_path"    { default = "../ocp/master.ign" }
variable "worker_ign_path"    { default = "../ocp/worker.ign" }

variable "aws_profile" { default = "" }
variable "infra_id"    { default = "" }

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null
}
