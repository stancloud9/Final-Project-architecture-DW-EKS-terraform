
locals {
  eks_worker_names = {
    "i-047852b5874fc56c6" = "eks-worker-01"
    "i-0533d3249e8f6df92" = "eks-worker-02"
    "i-0737af23b2c24ea34" = "eks-worker-03"
    "i-09cd252971a4c0338" = "eks-worker-04"
    "i-0d036e5b508f9feac" = "eks-worker-05"
  }
}

resource "aws_ec2_tag" "eks_worker_names" {
  for_each = local.eks_worker_names

  resource_id = each.key
  key         = "Name"
  value       = each.value
}
