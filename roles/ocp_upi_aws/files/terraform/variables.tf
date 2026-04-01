terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null
}

# --- Cluster identity ---

variable "aws_region" {
  type        = string
  description = "AWS region for deployment"
}

variable "aws_profile" {
  type        = string
  default     = ""
  description = "AWS CLI profile name (empty = default credentials chain)"
}

variable "cluster_name" {
  type        = string
  description = "OpenShift cluster name (used in DNS, resource naming, and tags)"
}

variable "base_domain" {
  type        = string
  description = "Base DNS domain (must have a public Route53 hosted zone)"
}

variable "infra_id" {
  type        = string
  default     = ""
  description = "Infrastructure ID from openshift-install manifests"
}

# --- Network ---

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "enable_dual_nic" {
  type        = bool
  default     = false
  description = "Create secondary ENIs with separate subnets for dual-NIC configuration"
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDR blocks allowed to SSH to nodes. Empty = VPC CIDR only"
}

variable "allowed_api_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to access the API server (6443)"
}

# --- Compute ---

variable "rhcos_ami" {
  type        = string
  description = "RHCOS AMI ID for the target region (resolved by Ansible)"
}

variable "bootstrap_instance_type" {
  type        = string
  default     = "m5.2xlarge"
  description = "EC2 instance type for the bootstrap node"
}

variable "master_instance_type" {
  type        = string
  default     = "m5.xlarge"
  description = "EC2 instance type for control plane nodes"
}

variable "master_count" {
  type        = number
  default     = 3
  description = "Number of control plane nodes (must be 3 for etcd quorum)"
}

variable "worker_instance_type" {
  type        = string
  default     = "m5.large"
  description = "EC2 instance type for worker nodes"
}

variable "worker_count" {
  type        = number
  default     = 3
  description = "Number of worker nodes"
}

variable "root_volume_size" {
  type        = number
  default     = 120
  description = "Root volume size in GB for all nodes"
}

variable "root_volume_type" {
  type        = string
  default     = "gp3"
  description = "Root volume type for all nodes"
}

# --- Ignition ---

variable "bootstrap_ign_path" {
  type        = string
  default     = "../ocp/bootstrap.ign"
  description = "Relative path to bootstrap ignition file"
}

variable "master_ign_path" {
  type        = string
  default     = "../ocp/master.ign"
  description = "Relative path to master ignition file"
}

variable "worker_ign_path" {
  type        = string
  default     = "../ocp/worker.ign"
  description = "Relative path to worker ignition file"
}

# --- S3 ---

variable "s3_force_destroy" {
  type        = bool
  default     = true
  description = "Allow S3 bucket deletion even when not empty"
}
