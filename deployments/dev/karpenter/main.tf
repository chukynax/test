provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source       = "../../../infrastructure/vpc"
  name_prefix  = var.name_prefix
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  az_count     = var.az_count
}
module "eks" {
  source              = "../../../infrastructure/eks"
  name_prefix         = var.name_prefix
  environment         = var.environment
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
}