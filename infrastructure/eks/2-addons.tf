data "aws_iam_policy_document" "vpc_cni_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
  }
}

resource "aws_iam_role" "vpc_cni_role" {
  name               = "${var.name_prefix}-vpc-cni-role"
  assume_role_policy = data.aws_iam_policy_document.vpc_cni_assume_role_policy.json

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni_role.name
}

resource "aws_iam_policy" "vpc_cni_additional" {
  name   = "${var.name_prefix}-vpc-cni-additional"
  policy = file("${path.module}/policies/vpc-cni-additional-policy.json")
}

resource "aws_iam_role_policy_attachment" "vpc_cni_additional" {
  policy_arn = aws_iam_policy.vpc_cni_additional.arn
  role       = aws_iam_role.vpc_cni_role.name
}

data "aws_iam_policy_document" "pod_identity_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:eks-pod-identity-agent"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
  }
}

resource "aws_iam_role" "pod_identity_role" {
  name               = "${var.name_prefix}-pod-identity-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role_policy.json

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_policy" "pod_identity_policy" {
  name   = "${var.name_prefix}-pod-identity-policy"
  policy = file("${path.module}/policies/pod-identity-policy.json")
}

resource "aws_iam_role_policy_attachment" "pod_identity_policy" {
  policy_arn = aws_iam_policy.pod_identity_policy.arn
  role       = aws_iam_role.pod_identity_role.name
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name         = aws_eks_cluster.control_plane.name
  addon_name           = "eks-pod-identity-agent"
  addon_version        = "v1.3.2-eksbuild.2"
  resolve_conflicts_on_create    = "OVERWRITE"
  
  service_account_role_arn = aws_iam_role.pod_identity_role.arn

  depends_on = [
    aws_eks_node_group.private_nodes,
    aws_iam_role_policy_attachment.pod_identity_policy
  ]

  tags = {
    Environment = var.environment
  }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name         = aws_eks_cluster.control_plane.name
  addon_name           = "vpc-cni"
  addon_version        = "v1.19.2-eksbuild.5"
  resolve_conflicts_on_create = "OVERWRITE"
  
  service_account_role_arn = aws_iam_role.vpc_cni_role.arn

  configuration_values = jsonencode({
    env = {
      ENABLE_POD_ENI = "true"
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET = "1"
      MINIMUM_IP_TARGET = "10"
      WARM_IP_TARGET = "3"
    }
  })

  depends_on = [
    aws_eks_addon.pod_identity,
    aws_iam_role_policy_attachment.vpc_cni_policy,
    aws_iam_role_policy_attachment.vpc_cni_additional
  ]

  tags = {
    Environment = var.environment
  }
}

data "aws_iam_policy_document" "ebs_csi_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
  }
}

resource "aws_iam_role" "ebs_csi_role" {
  name               = "${var.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role_policy.json

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_role.name
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.control_plane.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.37.0-eksbuild.1"
  resolve_conflicts_on_create        = "OVERWRITE"
  service_account_role_arn = aws_iam_role.ebs_csi_role.arn

  depends_on = [
    aws_eks_addon.pod_identity,
    aws_iam_role_policy_attachment.ebs_csi_policy
  ]

  tags = {
    Environment = var.environment
  }
}