###############################################################
# Minimal EKS cluster with one node group (t3.small)
# Everything in one file for clarity
###############################################################

terraform {
  required_version = ">= 1.6.0"

  ## Specify the required providers (which plugins terraform will use)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

## tells terraform which AWS region to use
provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {}

# --------------------------------------
# VPC + Subnets (uses AWS official module)
# Creates a tiny VPC: one CIDR block (10.0.0.0/16).
# Two public subnets (10.0.1.0/24, 10.0.2.0/24) across the first two AZs.
# No NAT Gateway (enable_nat_gateway = false) → keeps cost down.
# Public subnets mean instances can get public IPs and talk to the internet directly (so your node can pull images from GHCR) without a NAT.
# The module also wires up the Internet Gateway and route tables for you.
# Why public subnets? Simplicity and cost. 
# We not exposing a LoadBalancer; you’ll use kubectl port-forward. 
# --------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "devops-practice-vpc"
  cidr = "10.0.0.0/16"

  # EKS needs ≥2 subnets/AZs
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]

  map_public_ip_on_launch = true

  enable_nat_gateway = false
  single_nat_gateway = false

  tags = {
    Project = "devops-practice"
  }
}

# --------------------------------------
# EKS Cluster + Node Group
# Provisions the managed EKS control plane (AWS runs API server/etcd for you).
# Attaches the cluster to the VPC + subnets you just created.
# Creates a managed node group with one EC2 instance:
# instance_types = ["t3.small"] → cheap, 2 vCPU / 2GB RAM (fine for a demo)
# desired_size = 1 (+ min/max 1) → exactly one worker node
# Cluster version (1.30) pins Kubernetes minor version so it’s stable.
# “Managed node group” means AWS handles bootstrapping the node, 
# joining it to the cluster, and upgrades—less to maintain.
# --------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = "devops-practice-cluster"
  cluster_version = "1.30"

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  subnet_ids = module.vpc.public_subnets
  vpc_id     = module.vpc.vpc_id

  eks_managed_node_groups = {
    main = {
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
    }
  }

  tags = {
    Project = "devops-practice"
  }
}

# --------------------------------------
# Output basic info
# Print handy values after apply
# --------------------------------------
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "region" {
  value = "us-east-1"
  description = "AWS region where EKS is deployed"
}
