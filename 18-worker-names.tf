
locals {
  eks_worker_names = {
    "i-0e20491afd9b6d9fc" = "eks-worker-01"
    "i-0a5172bbbd5666413" = "eks-worker-02"
    "i-0c710f5ce40b27b63" = "eks-worker-03"
    "i-049b05afb9714ca4c" = "eks-worker-04"
    "i-04136588889405e05" = "eks-worker-05"
  }
}

resource "aws_ec2_tag" "eks_worker_names" {
  for_each = local.eks_worker_names

  resource_id = each.key
  key         = "Name"
  value       = each.value
}
