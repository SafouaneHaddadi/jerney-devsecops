# Jerney DevSecOps — Blog App on AWS EKS

A blog application (React + Node.js + PostgreSQL) deployed on AWS EKS, with a CI/CD pipeline that runs security checks automatically on every push.

---

## Project Overview

This is a personal project to learn DevSecOps in practice. The goal was to build a real pipeline with security integrated at each step, and deploy on Kubernetes using GitOps with ArgoCD.

The application is a simple blog where users can read and write posts. It's split into three services: a React frontend, a Node.js backend, and a PostgreSQL database.

---

## Architecture

```
Developer
    |
    |  git push
    v
GitHub Actions (CI Pipeline)
    |
    |-- Stage 1: ESLint (code quality)
    |-- Stage 2: npm audit (dependency scan)
    |-- Stage 3: Docker Build & Push to GHCR
    |-- Stage 4: Trivy (image vulnerability scan)
    |-- Stage 5: Checkov (Terraform + K8s scan)
    |-- Stage 6: Hadolint (Dockerfile lint)
    |-- Stage 7: Update K8s manifests (new image tag)
                |
                |  git commit [skip ci]
                v
            ArgoCD (GitOps)
                |
                v
            AWS EKS Cluster
                |
                |-- jerney-frontend (Nginx, 2 replicas)
                |-- jerney-backend (Node.js, 2 replicas)
                |-- jerney-db (PostgreSQL, StatefulSet)
```

---

## Tech Stack

| Layer | Tool |
|---|---|
| Cloud | AWS (EKS, VPC, EBS, ALB) |
| Infrastructure as Code | Terraform |
| Container Orchestration | Kubernetes (EKS Auto Mode) |
| GitOps / CD | ArgoCD |
| CI Pipeline | GitHub Actions |
| Container Registry | GitHub Container Registry (GHCR) |
| Frontend | React + Vite + Nginx |
| Backend | Node.js + Express |
| Database | PostgreSQL 16 |
| Code Quality | ESLint |
| Dependency Audit | npm audit |
| Image Scanning | Trivy |
| IaC Scanning | Checkov |
| Dockerfile Linting | Hadolint |
| Storage | AWS EBS (gp3, encrypted) |

---

## Security

Each layer has a security check.

- **Code**: ESLint catches bad patterns before anything is built.
- **Dependencies**: npm audit scans third-party packages for known vulnerabilities.
- **Docker images**: Trivy scans the built images for OS and library CVEs.
- **Dockerfiles**: Hadolint checks that Dockerfiles follow safe practices (non-root user, pinned versions, etc.).
- **Infrastructure**: Checkov scans Terraform and Kubernetes files for misconfigurations.
- **Kubernetes runtime**:
  - NetworkPolicies: frontend can only talk to backend, backend can only talk to the database.
  - All pods run as non-root users.
  - Backend and frontend have a read-only root filesystem.
  - All Linux capabilities are dropped.
  - Database credentials are stored in Kubernetes Secrets, not hardcoded.
  - EBS volumes are encrypted at rest.
  - Resource limits are set on all pods.

---

## Infrastructure (Terraform)

```
terraform/
├── bootstrap/
│   └── main.tf                  # S3 state bucket + DynamoDB lock table
├── environments/
│   ├── dev/
│   │   ├── argocd.tf            # ArgoCD install + Application
│   │   ├── main.tf              # VPC + EKS modules
│   │   ├── outputs.tf
│   │   ├── provider.tf
│   │   ├── terraform.tfvars
│   │   └── variables.tf
│   └── prod/                    # (not deployed)
└── modules/
    ├── eks/
    │   ├── main.tf
    │   ├── outputs.tf
    │   └── variables.tf
    └── vpc/
        ├── main.tf
        ├── outputs.tf
        └── variables.tf
```

- EKS Auto Mode: AWS handles node provisioning and scaling automatically.
- Worker nodes are in private subnets, load balancers in public subnets.
- Terraform state stored remotely in S3 with DynamoDB locking.
- EKS secrets encrypted with KMS.

---

## Kubernetes Resources

```
k8s/
├── 00-namespace.yml             # jerney namespace
├── 01-secret.yml                # DB credentials (base64)
├── 02-storage-class.yml         # EBS gp3 StorageClass
├── 04-db-statefulset.yml        # PostgreSQL StatefulSet + volumeClaimTemplates
├── 05-db-service.yml            # ClusterIP service for DB
├── 06-backend-deployment.yml    # Node.js backend (2 replicas)
├── 07-backend-service.yml       # ClusterIP service for backend
├── 08-frontend-deployment.yml   # Nginx frontend (2 replicas)
├── 09-frontend-service.yml      # LoadBalancer service (AWS ALB)
├── 10-networkpolicy-db.yml      # DB: allow only from backend
├── 11-networkpolicy-backend.yml # Backend: allow only from frontend
└── 12-rbac.yml                  # ServiceAccounts, Roles, RoleBindings
```

- PostgreSQL uses a StatefulSet so the pod always gets the same volume after a restart.
- An initContainer runs before PostgreSQL starts to fix EBS volume permissions.
- An initContainer on the backend waits for the database to be ready before starting.
- Frontend and backend use RollingUpdate so there is no downtime during deployments.

---

## CI/CD Pipeline

Every `git push` triggers this flow:

```
git push
    |
    v
[Stage 1] Lint (ESLint)              -- continue-on-error
    |
    v
[Stage 2] SCA (npm audit)            -- continue-on-error
    |
    v
[Stage 3] Build & Push (Docker -> GHCR)
    |  tags: <sha>, <branch>, latest
    v
[Stage 4] Image Scan (Trivy)         -- continue-on-error
    |
    |-- [Stage 5] IaC Scan (Checkov)
    |-- [Stage 6] Dockerfile Lint (Hadolint)
    |
    v
[Stage 7] Update K8s Manifests
    |  replace image tag with github.sha
    |  git commit [skip ci]
    |  git push
    v
ArgoCD detects new commit on main
    |
    v
Rolling update on EKS -> Healthy
```

Git is the single source of truth. No `kubectl apply` is ever run manually. ArgoCD checks for changes every 3 minutes and applies them automatically. If someone changes something directly on the cluster, ArgoCD reverts it (`selfHeal: true`).

---

## How to Deploy

### Prerequisites
- AWS CLI configured
- Terraform >= 1.7
- kubectl
- Helm

### Step 1 — Bootstrap the state backend
```bash
cd terraform/bootstrap
terraform init
terraform apply
```

### Step 2 — Deploy VPC + EKS + ArgoCD
```bash
cd terraform/environments/dev
terraform init
terraform apply

# Configure kubectl
aws eks update-kubeconfig --region eu-west-1 --name jerney-eks-dev
```

### Step 3 — Deploy the ArgoCD Application
```bash
# Uncomment kubernetes_manifest.argocd_application in argocd.tf
terraform apply
```

### Step 4 — Access ArgoCD
```bash
terraform output argocd_server_url
terraform output argocd_admin_password
```

ArgoCD will automatically detect the `k8s/` folder and deploy all resources.

---

## Problems Encountered

Issues I ran into during the project and how I fixed them.

| Problem | Cause | Fix |
|---|---|---|
| PVC stuck in `Pending` — `no topology key found` | EKS Auto Mode uses a different EBS driver than what I had configured | Changed the StorageClass provisioner to `ebs.csi.eks.amazonaws.com` + set `WaitForFirstConsumer` |
| `chmod: Operation not permitted` on PostgreSQL startup | EKS Auto Mode does not apply `fsGroup` to EBS volumes, so the volume was mounted as root | Added an initContainer that runs as root and fixes permissions before Postgres starts |
| `InvalidImageName` on frontend pod | `github.repository` returns the repo name with uppercase letters, GHCR only accepts lowercase | Added a lowercase conversion step in the pipeline |
| Wrong image SHA written to manifest | `git rev-parse HEAD` returns the SHA of the bot's commit, not the build commit | Switched to `github.sha` which always refers to the commit that triggered the pipeline |
| ArgoCD `Application` CRD not found during `terraform apply` | Terraform tried to create the ArgoCD Application before ArgoCD had finished installing | Split into two separate `terraform apply` runs |
| LoadBalancer not accessible from internet | Missing annotation to make the ALB internet-facing | Added `service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing` |
| GitHub packages set back to private | Packages inherit the repo visibility — the repo was private at the time | Set packages to public manually |
| `npm ci` failing in Docker build | `eslint-plugin-react` has a peer dependency conflict with ESLint v10 | Added `--legacy-peer-deps` to the `npm ci` command in the Dockerfile |
| Nginx `bind() failed` on port 80 | Ports below 1024 require root — the container was running as UID 101 | Changed Nginx to listen on port 8080 instead |
| `$(POSTGRES_USER)` not resolved in liveness probe | Kubernetes does not expand env vars inside `exec` probe commands | Replaced the variable with the hardcoded value in the probe |

---

## Cleanup

To delete everything and stop AWS costs:

```bash
# Delete Kubernetes workloads
kubectl delete namespace jerney
kubectl delete namespace argocd

# Destroy the EKS cluster and VPC
cd terraform/environments/dev
terraform destroy -auto-approve

# Destroy the state backend (only if fully done with the project)
cd ../../bootstrap
terraform destroy -auto-approve
```

---
## What's Next

I'm planning to add an observability stack to make the project more complete — Prometheus to collect metrics from the cluster and the pods, Grafana to visualize them with dashboards, and Loki for log aggregation. The goal is to be able to monitor the health of the application in real time and set up alerts, which is something missing from the current setup.
