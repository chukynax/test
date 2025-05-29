# Innovate Inc. — AWS Cloud Architecture Design

## Overview

Innovate Inc.
Requirements: security, scalability, fault tolerance, and cost-effective cloud deployment.


## AWS Account Structure

Three **AWS accounts** are used, each with a dedicated role and isolation:

| Account | Purpose         | Comment                            |
| ------- | --------------- | ---------------------------------- |
| `dev`   | Development     | Fast iteration, feature branches   |
| `stage` | Staging/Testing | Close to production, smoke tests   |
| `prod`  | Production      | Only stable code, maximum security |

* Each account has its own budget and cost alerts.
* Managed via AWS Organizations and SCP (Service Control Policies).


## VPC and Network Design

Each environment has its own **VPC**:

* **3 Availability Zones** for high availability
* **6 subnets**: 3 public (ALB, NAT GW) and 3 private (EKS, RDS)

```
VPC CIDR: 10.0.0.0/16
  - Public Subnets:   10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
  - Private Subnets:  10.0.48.0/20, 10.0.64.0/20, 10.0.80.0/20
```

### Network Security

* **NACLs and Security Groups** to restrict traffic
* **NAT Gateway** in public subnets for outbound traffic from private nodes
* **VPC Endpoints (Interface + Gateway)** for private access to AWS services like S3, ECR
* **WAF + ALB** for request filtering and TLS termination at entry point


## EKS Cluster (Kubernetes)

* Cluster deployed using **Terraform** (IaC)
* Kubernetes version >=1.28
* OIDC enabled for IAM Roles for Service Accounts (IRSA)
* **Cluster Autoscaler** installed via Helm and configured with Auto Scaling Group

### Node Groups

* 1 system node group (Graviton t4g.medium or t3.medium)
* 1 application node group (includes Spot instances for non-critical workloads)
* Auto-scaling: min 2, max 10 nodes


## Dedicated Infra Cluster

There is a separate Kubernetes cluster dedicated to infrastructure monitoring and management components. It includes:

* **ArgoCD** — GitOps controller
* **Grafana** — dashboards and visualization
* **VictoriaMetrics** — Prometheus-compatible metrics storage (agent deployed on all nodes)
* **Alertmanager** — for alert routing
* **Loki** — centralized log collection, storing logs in **S3 (via BoltDB Shipper)** for cost efficiency

### GitLab Runners Deployment Strategy

GitLab Runners will deployed on regular EC2 On-Demand instances. This approach is necessary because:

* On-Demand instances provide stable and uninterrupted runtime, which is critical during container builds and test execution.
* Spot instances are not suitable here due to their potential to be terminated at any moment, even in the middle of builds or tests, causing job failures and wasting resources.
* Using stable On-Demand instances ensures reliable CI/CD pipelines and consistent build results.


## Database

Using **Amazon RDS PostgreSQL**:

* **Multi-AZ** enabled for high availability (standby instance in different AZ)
* Automated daily **backups**, retained for 7–14 days
* Point-in-time recovery (PITR)
* **Optional cross-region replication** for disaster recovery
* Encryption at rest using **KMS**

Amazon RDS was selected as a managed PostgreSQL solution to reduce operational overhead and accelerate time to market:

* Automated patching, backups, and failover handled by AWS
* Built-in Multi-AZ support without manual replication setup
* Vertical scaling and support for read replicas
* Seamless integration with KMS, IAM, CloudWatch, and other AWS services
* Suitable for most production workloads without the need to manage the database server manually


## Security and audit

* OIDC enabled on EKS for **IAM Roles for Service Accounts (IRSA)**
* IAM policies follow **least privilege** principle
* **GuardDuty** for threat detection (port scans, unusual API calls, etc.)
* **AWS Security Hub** for centralized security posture management
* **AWS CloudTrail** logs all API calls (CLI, SDK, console)
* **IAM Access Analyzer** and **Config Rules** enforce best practices
* Designed with **PCI-DSS** compliance in mind (encryption, access control, auditing)


## Cost Optimization

* Use of **Graviton2/3** (ARM64) instances for up to 40% cost savings
* **Spot instances** for non-critical workloads (CI jobs, dev env, logging)
* **Budgets** and **Cost Anomaly Detection** for expense monitoring
* **Savings Plans** or Reserved Instances for stable production workloads


## Monitoring

* **VictoriaMetrics (Prometheus-compatible)** collects metrics
* **Grafana** for dashboards (pods, nodes, DB, app health)
* **Alertmanager** alerts on CPU, memory, errors, downtime
* **Loki + Grafana** for searchable centralized logging


## Deployment Flow

1. Developer **pushes to Git** repository  
2. **Some CI** (such as Gitlab CI / Jenkins / Github Actions) builds Docker image, runs product tests and security scans (e.g., **SonarQube** for code quality, **Trivy** for container vulnerability scanning), then pushes image to **Amazon ECR**  
3. **ArgoCD Image updater** detects new image tag, patches Kustomize manifests and commits back to Git  
4. **ArgoCD** synchronizes changes from Git and applies them to the cluster  


## Summary

* Environment isolation (`dev`, `stage`, `prod`)
* Infrastructure as Code (Terraform / Terragrunt)
* GitOps CI/CD pipeline with ArgoCD + Kustomize
* Secrets in-repo encryption via `git-crypt` and in-cloud use via Amazon Secrets Manager
* Logs and metrics stored in S3 for cost savings
* Secure and scalable RDS PostgreSQL
* Centralized monitoring and logging
* Cost-efficient and highly available Kubernetes setup
