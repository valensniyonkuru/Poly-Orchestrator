terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
  backend "s3" {
    bucket         = "shopnow-tfstate"
    key            = "shopnow/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "shopnow-tf-lock"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "ShopNow"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ── VPC ─────────────────────────────────────────────────────────────────────
module "vpc" {
  source      = "./modules/vpc"
  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  azs         = var.availability_zones
}

# ── ECS (Fargate) ───────────────────────────────────────────────────────────
module "ecs" {
  source          = "./modules/ecs"
  project         = var.project
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  public_subnets  = module.vpc.public_subnet_ids
  private_subnets = module.vpc.private_subnet_ids
  ecr_frontend    = var.ecr_frontend_image
  ecr_backend     = var.ecr_backend_image
  db_password     = var.db_password
}

# ── EKS ─────────────────────────────────────────────────────────────────────
module "eks" {
  source          = "./modules/eks"
  project         = var.project
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnet_ids
  public_subnets  = module.vpc.public_subnet_ids
  k8s_version     = var.eks_kubernetes_version
}
