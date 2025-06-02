data "aws_iam_policy_document" "karpenter_controller_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.name_prefix}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role_policy.json
}

resource "aws_iam_policy" "karpenter_controller" {
  name   = "KarpenterController"
  policy = file("${path.module}/policies/karpenter-controller-policy.json")
}

resource "aws_iam_policy" "karpenter_eks_describe" {
  name = "${var.name_prefix}-karpenter-eks-describe"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "EKSDescribeCluster",
        Effect = "Allow",
        Action = [
          "eks:DescribeCluster"
        ],
        Resource = "arn:aws:eks:eu-west-1:${data.aws_caller_identity.current.account_id}:cluster/${aws_eks_cluster.control_plane.name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_policy_attach" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

resource "aws_iam_role_policy_attachment" "karpenter_eks_describe_attach" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_eks_describe.arn
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile"
  role = aws_iam_role.nodes.name
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.control_plane.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.control_plane.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.control_plane.name]
    }
  }
}

resource "helm_release" "karpenter_oci" {
  name             = "karpenter"
  chart            = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  version          = "1.5.0"

  namespace        = "karpenter"
  create_namespace = true

  set {
    name  = "settings.clusterName"
    value = aws_eks_cluster.control_plane.name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = aws_eks_cluster.control_plane.endpoint
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }

  set {
    name  = "settings.aws.defaultInstanceProfile"
    value = aws_iam_instance_profile.karpenter.name
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "1"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "1Gi"
  }

  set {
    name  = "controller.resources.limits.cpu"
    value = "1"
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "1Gi"
  }
  set {
    name  = "replicaCount"
    value = "1"
  }
  set {
    name  = "settings.interruptionQueueName"
    value = aws_sqs_queue.karpenter_interruption_queue.name
  }
  depends_on = [aws_eks_node_group.private_nodes]
}

resource "aws_sns_topic" "spot_interruption_topic" {
  name       = "spot-interruption-topic.fifo"
  fifo_topic = true
}

resource "aws_sqs_queue" "karpenter_interruption_queue" {
  name                        = "karpenter-interruption-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}

locals {
  karpenter_sqs_policy = replace(
    replace(
      file("${path.module}/policies/karpenter-sqs-policy.json"),
      "QUEUE_ARN_PLACEHOLDER",
      aws_sqs_queue.karpenter_interruption_queue.arn
    ),
    "TOPIC_ARN_PLACEHOLDER",
    aws_sns_topic.spot_interruption_topic.arn
  )
}

resource "aws_sqs_queue_policy" "karpenter_interruption_queue_policy" {
  queue_url = aws_sqs_queue.karpenter_interruption_queue.id
  policy    = local.karpenter_sqs_policy
}

resource "aws_sns_topic_subscription" "sqs_karpenter" {
  topic_arn = aws_sns_topic.spot_interruption_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.karpenter_interruption_queue.arn
}

resource "aws_iam_role_policy_attachment" "amazon-sqs-access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
  role       = aws_iam_role.karpenter_controller.name
}

resource "aws_security_group" "karpenter_sg" {
  name        = "${var.name_prefix}-karpenter-sg"
  description = "Security group for Karpenter-managed nodes"
  vpc_id      = aws_eks_cluster.control_plane.vpc_config[0].vpc_id

  ingress {
    description = "Kubernetes API"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Node SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Cluster internal communication"
    protocol    = "-1" # All traffic
    from_port   = 0
    to_port     = 0
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    "karpenter.sh/discovery" = "karpenter-eks"
    Name                     = "${var.name_prefix}-karpenter-sg"
    Environment              = var.environment
  }
}