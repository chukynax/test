data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_role" {
  name               = "${var.name_prefix}-eks-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_role.name
}

resource "aws_eks_cluster" "control_plane" {
  name     = "${var.name_prefix}-eks"
  role_arn = aws_iam_role.eks_role.arn
  version  = "1.32"

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = false
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  depends_on = [aws_iam_role.eks_role]
}

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.control_plane.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.control_plane.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}

data "aws_caller_identity" "current" {}