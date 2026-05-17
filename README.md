# Week 6 — Day 39

# Advanced CI/CD Patterns (Production-Grade DevOps Project)

A complete production-style CI/CD platform demonstrating:

* Blue-Green Deployments
* Feature Flags
* Automated Smoke Testing
* Automated Rollbacks
* DORA Metrics
* Promotion Pipelines
* GitHub Actions CI/CD
* Kubernetes Deployment Strategies
* Zero-Downtime Database Migrations
* Redis-backed Feature Management
* Observability-Driven Deployments

This project is intentionally designed to teach real-world deployment engineering concepts used by companies like:

* Netflix
* Amazon
* Google
* Uber
* Spotify

---

# What You Will Learn

By completing this project, you will understand:

| Topic                     | Why It Matters                         |
| ------------------------- | -------------------------------------- |
| CI/CD Fundamentals        | Core DevOps delivery pipeline concepts |
| Blue-Green Deployments    | Zero-downtime production releases      |
| Feature Flags             | Safe gradual feature rollout           |
| Smoke Testing             | Automated deployment validation        |
| Auto Rollback             | Fast recovery from failed deployments  |
| Promotion Pipelines       | Safe multi-environment delivery        |
| Kubernetes Deployments    | Production orchestration patterns      |
| GitHub Actions            | Enterprise CI/CD automation            |
| DORA Metrics              | Measuring engineering performance      |
| Expand-Contract Migration | Zero-downtime database changes         |

---

# CI/CD — Deep Understanding

## What is CI?

CI = Continuous Integration.

Definition:

Continuous Integration is the practice of frequently merging developer changes into a shared repository while automatically validating each change using:

* builds
* tests
* linting
* security checks

Goal:

Catch integration problems early.

Without CI:

```text
Developer A works for 2 weeks
Developer B works for 2 weeks
Merge happens
Massive conflicts occur
Production breaks
```

With CI:

```text
Small changes merged frequently
Problems detected immediately
Lower integration risk
Faster delivery
```

---

## What is Continuous Delivery?

Every successful build is:

* tested
* packaged
* deployment-ready

Production deployment may still require manual approval.

---

## What is Continuous Deployment?

Every successful build automatically deploys to production.

No manual approval.

This requires:

* extremely strong test coverage
* observability
* automated rollback
* deployment confidence

---

# Why Advanced CI/CD Patterns Matter

Basic deployment:

```text
push → build → test → deploy
```

This becomes dangerous at scale.

Advanced patterns solve:

| Problem                     | Solution                 |
| --------------------------- | ------------------------ |
| Risky deployments           | Blue-Green / Canary      |
| Unsafe feature releases     | Feature Flags            |
| Broken deployments          | Automated Rollback       |
| Database migration downtime | Expand-Contract Pattern  |
| Unknown deployment health   | Smoke Tests + Monitoring |
| Unsafe production releases  | Promotion Pipelines      |

---

# Feature Flags — The Most Important Pattern

## Core Insight

```text
Deploying code ≠ Releasing feature
```

Without feature flags:

```text
Deploy code
↓
ALL users immediately affected
↓
Rollback requires redeployment
```

With feature flags:

```text
Deploy code safely
↓
Feature disabled initially
↓
Enable gradually:
1% → 10% → 50% → 100%
↓
Disable instantly if broken
```

---

# Deployment Strategies

## Rolling Update

Default Kubernetes deployment strategy.

```text
[v1][v1][v1]
↓
[v2][v1][v1]
↓
[v2][v2][v1]
↓
[v2][v2][v2]
```

Pros:

* simple
* resource efficient

Cons:

* mixed versions simultaneously
* risky for breaking changes

---

## Blue-Green Deployment

Two environments exist simultaneously:

| Environment | Purpose            |
| ----------- | ------------------ |
| Blue        | Current production |
| Green       | New version        |

Traffic switch happens instantly.

Advantages:

* zero downtime
* instant rollback
* safer releases

Tradeoff:

* temporarily doubles infrastructure usage

---

## Canary Deployment

Traffic split between:

* stable version
* new version

Example:

```text
90% → stable
10% → canary
```

Benefits:

* limits blast radius
* validates at real production scale
* safer gradual rollout

---

# Expand-Contract Migration Pattern

The most important database migration pattern.

## Wrong Approach

```text
Deploy code expecting new column
Old code still uses old schema
Application crashes
```

---

## Correct Approach

### Phase 1 — Expand

Add new schema in backward-compatible way.

### Phase 2 — Migrate

Backfill data.

### Phase 3 — Contract

Move all code to new schema.

### Phase 4 — Cleanup

Remove old schema.

Result:

```text
Zero downtime migration
```

---

# DORA Metrics

The 4 metrics used to measure DevOps performance.

| Metric               | Meaning                  |
| -------------------- | ------------------------ |
| Deployment Frequency | How often you deploy     |
| Lead Time            | Commit → Production time |
| Change Failure Rate  | % of bad deployments     |
| MTTR                 | Mean Time To Recovery    |

---

# Project Architecture

```text
Developer Push
       ↓
GitHub Actions CI
       ↓
Tests + Security Scan
       ↓
Docker Build
       ↓
Blue-Green Deployment
       ↓
Smoke Tests
       ↓
Monitoring + Rollback
       ↓
Production Traffic Switch
```

---

# Technology Stack

| Component      | Purpose                 |
| -------------- | ----------------------- |
| FastAPI        | Backend service         |
| Redis          | Storage + Feature Flags |
| Kubernetes     | Orchestration           |
| Minikube       | Local Kubernetes        |
| Docker         | Containerization        |
| GitHub Actions | CI/CD                   |
| Helm           | Kubernetes packaging    |
| Python         | Automation scripts      |

---

# Prerequisites

Install:

| Tool         | Required |
| ------------ | -------- |
| Docker       | Yes      |
| kubectl      | Yes      |
| Minikube     | Yes      |
| Helm         | Yes      |
| Python 3.11+ | Yes      |
| Git          | Yes      |
| curl         | Yes      |

Verify:

```bash
which docker
which kubectl
which minikube
which helm
which python3
```

---

# Recommended Machine Specs

| Resource | Minimum |
| -------- | ------- |
| RAM      | 8 GB    |
| CPU      | 4 vCPU  |
| Disk     | 20 GB   |

---

# Step 1 — Clone Repository

```bash
git clone <your-repo-url>
cd day39-cicd
```

---

# Step 2 — Start Kubernetes Cluster

```bash
minikube start \
  --driver=docker \
  --memory=4096 \
  --cpus=4 \
  --kubernetes-version=v1.29.0
```

Verify:

```bash
kubectl cluster-info
kubectl get nodes
```

---

# Step 3 — Create Project Structure

```bash
mkdir -p \
  app \
  app/migrations \
  kubernetes/base \
  kubernetes/blue \
  kubernetes/green \
  .github/workflows \
  scripts \
  tests \
  feature-flags
```

---

# Step 4 — Build Docker Images

Minikube uses its own Docker daemon.

IMPORTANT:

```bash
eval $(minikube docker-env)
```

Build blue image:

```bash
docker build \
  -t url-shortener:blue \
  -t url-shortener:v1.0.0 \
  .
```

Build green image:

```bash
docker build \
  -t url-shortener:green \
  -t url-shortener:v1.1.0 \
  .
```

Verify:

```bash
docker images | grep url-shortener
```

---

# Step 5 — Deploy Redis

Apply namespace:

```bash
kubectl apply -f kubernetes/base/namespace.yaml
```

Deploy Redis:

```bash
kubectl apply -f kubernetes/base/redis.yaml
```

Verify:

```bash
kubectl get pods -n url-shortener
```

Expected:

```text
redis pod = Running
```

---

# Step 6 — Deploy Blue Environment

Deploy current stable version:

```bash
kubectl apply -f kubernetes/blue/deployment.yaml
```

Verify:

```bash
kubectl get pods -n url-shortener -l color=blue
```

---

# Step 7 — Create Services

Apply services:

```bash
kubectl apply -f kubernetes/base/service.yaml
```

Verify:

```bash
kubectl get svc -n url-shortener
```

---

# Step 8 — Access Application

IMPORTANT:

If running Minikube with Docker driver inside EC2, NodePort may fail.

Use port-forward:

```bash
kubectl port-forward \
  svc/url-shortener \
  -n url-shortener \
  8080:80
```

Open:

```text
http://localhost:8080
```

---

# Step 9 — Verify Health

```bash
curl http://localhost:8080/health
```

Expected:

```json
{
  "status": "healthy"
}
```

---

# Step 10 — Run Smoke Tests

```bash
bash tests/smoke-test.sh \
  http://localhost:8080 \
  1.0.0 \
  blue
```

Validates:

* health
* readiness
* version
* redirects
* feature flags
* metrics
* error handling

---

# Step 11 — Blue-Green Deployment

Deploy new version:

```bash
bash scripts/blue-green-deploy.sh
```

What happens internally:

1. Detect active color
2. Deploy inactive color
3. Wait for readiness
4. Run smoke tests
5. Switch production traffic
6. Keep old version for rollback

---

# Step 12 — Automated Rollback

Monitor deployment:

```bash
bash scripts/auto-rollback.sh
```

Purpose:

* monitor production health
* rollback automatically if error rate increases

This simulates real production deployment safety.

---

# Step 13 — Database Migration

Run migration:

```bash
bash scripts/run-migrations.sh
```

Demonstrates:

* expand-contract pattern
* zero downtime schema evolution
* backward compatibility

---

# Step 14 — GitHub Actions Pipeline

Pipeline stages:

```text
Checkout
↓
Unit Tests
↓
Linting
↓
Build Docker Image
↓
Security Scan
↓
Deploy to Dev
↓
Smoke Tests
↓
Deploy to Production
↓
Post-Deploy Monitoring
```

---

# GitHub Actions Features

This project demonstrates:

* reusable pipelines
* environment promotion
* manual approvals
* artifact passing
* Docker image publishing
* security scanning
* deployment protection

---

# Step 15 — Promotion Pipeline

Promote image:

```bash
GitHub Actions → Promote Workflow
```

Flow:

```text
dev → staging → production
```

Benefits:

* validated artifacts
* safer releases
* auditability

---

# Step 16 — DORA Metrics

Run:

```bash
bash scripts/dora-metrics.sh
```

Outputs:

* deployment frequency
* lead time
* MTTR
* change failure rate

---

# Important Production Engineering Lessons

## 1. Deployment != Release

Feature flags separate deployment from user exposure.

This is foundational to modern delivery systems.

---

## 2. Health Checks Matter

Difference:

| Probe     | Purpose            |
| --------- | ------------------ |
| Liveness  | Is process alive?  |
| Readiness | Ready for traffic? |

---

## 3. Observability Drives Reliability

Production deployments require:

* monitoring
* metrics
* rollback automation
* deployment verification

---

## 4. Fast Rollback Is Critical

Elite teams optimize:

```text
Recovery speed > preventing every failure
```

---

# Common Troubleshooting Commands

## Pods

```bash
kubectl get pods -A
```

---

## Services

```bash
kubectl get svc -A
```

---

## Logs

```bash
kubectl logs -n url-shortener <pod-name>
```

---

## Describe Pod

```bash
kubectl describe pod <pod-name> -n url-shortener
```

---

## Rollout Status

```bash
kubectl rollout status deployment/url-shortener-blue -n url-shortener
```

---

## Rollback

```bash
kubectl rollout undo deployment/url-shortener-green -n url-shortener
```

---

# Interview Questions This Project Helps Answer

## Kubernetes

* Rolling updates vs blue-green
* Liveness vs readiness
* Service selectors
* Deployment strategies
* Scaling workloads

---

## CI/CD

* How feature flags work
* How automated rollback works
* Promotion pipeline design
* Deployment verification strategies
* GitHub Actions architecture

---

## SRE / Reliability

* MTTR reduction
* Incident recovery
* Safe deployments
* DORA metrics
* Observability-driven delivery

---

# Real-World Improvements

Future enhancements:

* ArgoCD GitOps
* Canary analysis with Flagger
* Service mesh
* OpenTelemetry tracing
* Chaos engineering
* Progressive delivery
* Vault secrets management
* Multi-cluster deployment
* Terraform infrastructure automation

---

# Cleanup

Delete resources:

```bash
kubectl delete namespace url-shortener
```

Stop Minikube:

```bash
minikube stop
```

Delete cluster:

```bash
minikube delete
```

---

# Key Takeaway

This project demonstrates modern platform engineering principles.

The core lesson is:

```text
Reliable software delivery is not just about deploying code.

It is about:
- safety
- observability
- rollback
- verification
- automation
- controlled risk
```

That is the foundation of production-grade DevOps and SRE engineering.

---

# Author

Built as a production-grade Advanced CI/CD capstone project for DevOps/SRE learning and interview preparation.
