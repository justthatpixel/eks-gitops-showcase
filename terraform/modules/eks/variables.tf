variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  description = "Kubernetes version. Default to the NEWEST version EKS offers, for two reasons: (1) standard support runs 14 months from release, so newest = longest runway before the control plane silently jumps from $0.10/hr to $0.60/hr on extended support — 6x, and the largest line item in this stack; (2) it matches the local kind cluster (kind-cluster.yaml pins kindest/node v1.36.x), so local testing rehearses the same API surface. Check for anything newer before applying: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html"
  type        = string
  default     = "1.36"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Nodes run in private subnets; the ALB Controller places load balancers in the public ones separately."
  type        = list(string)
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_capacity_type" {
  description = "\"ON_DEMAND\" or \"SPOT\". Spot cuts cost further for a demo cluster you're comfortable occasionally losing a node from (claude2.md #9)."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "cluster_enabled_log_types" {
  description = "EKS control-plane log streams sent to CloudWatch, billed at ~$0.50/GB ingested. Deliberately narrower than the upstream module's [\"audit\", \"api\", \"authenticator\"] default: `audit` writes a record per API call and dominates the bill on a cluster running ArgoCD + Prometheus. Set to [] to disable control-plane logging entirely."
  type        = list(string)
  default     = ["authenticator"]
}

variable "cluster_log_retention_days" {
  description = "Retention for the control-plane log group. The module defaults to 90 days; 7 is plenty for a demo where the logs are only read while debugging an auth failure."
  type        = number
  default     = 7
}
