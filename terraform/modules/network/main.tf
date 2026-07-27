# VPC: 2 AZs (matches claude2.md's cost-conscious spec — the minimum EKS +
# an internet-facing ALB both require, and each extra AZ is an extra
# private subnet + more NAT/ALB spread cost for a demo cluster that
# doesn't need the resilience). 2 public + 2 private subnets, symmetric.

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = [cidrsubnet(var.vpc_cidr, 4, 0), cidrsubnet(var.vpc_cidr, 4, 1)]
  private_subnets = [cidrsubnet(var.vpc_cidr, 4, 8), cidrsubnet(var.vpc_cidr, 4, 9)]

  # Internet Gateway is created automatically by this module for the
  # public subnets' route table (0.0.0.0/0 -> igw).
  #
  # NAT Gateway: REQUIRED for the private-subnet EKS nodes' own outbound
  # internet access (pulling images from Docker Hub/quay.io/registry.k8s.io,
  # reaching GitHub raw URLs, etc). This is a completely separate traffic
  # direction from the ALB (which only handles INBOUND requests routed to
  # in-VPC targets) — the ALB does not provide any outbound path, so this
  # is still needed even though the ALB sits in the public subnet.
  #
  # single_nat_gateway = true: one shared NAT Gateway across both AZs
  # instead of one-per-AZ (the HA default) — halves the NAT cost, trades
  # away multi-AZ NAT resilience. Acceptable for a demo cluster.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Required tags for the EKS + AWS Load Balancer Controller auto-discovery
  # to find the right subnets for internal vs internet-facing load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = var.tags
}

data "aws_availability_zones" "available" {
  state = "available"
}
