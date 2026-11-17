# deterministic-operations-api-canary-deployment / API Canary Deployment

[中文版](README.cn.md)

[![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-IAM%20Auth-red.svg)](https://support.huaweicloud.com/intl/en-us/)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](#)

> API Canary Deployment Reference Implementation
> API 金丝雀发布参考实践

---

## 1. Overview

This practice provides the core capability of **API Canary Deployment** for **low-risk version release and gray verification** scenarios. It is intended for DevOps / backend engineers and can be used as a reference architecture / learning sample / production template.

### Core Capabilities

- Dual-version parallel release: the same API deploys both a stable and a candidate backend, published to independent environments
- Explicit canary promotion: after validating the candidate, one click switches the prod environment API backend to the candidate function — idempotent and reversible
- Concise and portable: Terraform + FunctionGraph + APIG with no extra dependencies, ready for release pipelines

---

## 2. Table of Contents

- [1. Overview](#1-overview)
- [2. Table of Contents](#2-table-of-contents)
- [3. Architecture](#3-architecture)
- [4. Highlights](#4-highlights)
- [5. Involved Cloud Services](#5-involved-cloud-services)
- [6. Prerequisites](#6-prerequisites)
- [7. Quick Start](#7-quick-start-critical)
- [8. Step-by-step Deployment](#8-step-by-step-deployment)
- [9. Usage / Verification](#9-usage--verification-critical)
- [10. Clean Up Resources](#10-clean-up-resources)
- [11. Detailed Explanation](#11-detailed-explanation)
- [12. Dependencies](#12-dependencies)
- [13. FAQ / Troubleshooting](#13-faq--troubleshooting)
- [14. Contribution Guide](#14-contribution-guide)
- [15. License](#15-license-critical)
- [16. Contact / Maintainers](#16-contact--maintainers-critical)

---

## 3. Architecture

> Deploy both stable and candidate versions at once; observe the candidate in an isolated environment, then promote it as the stable backend after validation.

```
                            ┌────────────┐
                            │   Client   │
                            └──────┬─────┘
                                   │ HTTPS
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                 APIG Dedicated Instance (Gateway)                  │
│  onepod (candidate)  GET /hello    |    prod (stable)  GET /hello  │
└───────────────┬─────────────────────────────────────┬──────────────┘
                │                                     │
                ▼                                     ▼
┌──────────────────────────────┐      ┌──────────────────────────────┐
│  FunctionGraph hello-canary  │      │   FunctionGraph hello-prod   │
│  Candidate version (onepod)  │      │    Stable version (prod)     │
│ Returns: Hello from CANARY!  │      │  Returns: Hello from PROD!   │
└───────────────┬──────────────┘      └───────────────┬──────────────┘
                │                                     │
                └──────────────────┬──────────────────┘
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                          Canary Promotion                          │
│             terraform apply -var="promote_canary=true"             │
│       prod environment API backend switches to hello-canary        │
└────────────────────────────────────────────────────────────────────┘
```

**Key Components**:
- APIG Dedicated Instance: API gateway entry, hosting API definitions, environments and publication
- Environments `onepod` / `prod`: isolated release environments for candidate and stable versions
- FunctionGraph `hello-canary` / `hello-prod`: candidate and stable business functions
- Promotion flag `promote_canary`: switches the prod environment API backend to the candidate function

---

## 4. Highlights

- **Low-risk release**: the candidate version is fully isolated and receives no production traffic; risk converges to an explicit promotion action
- **One-click promote and rollback**: the `promote_canary` flag controls the backend target and can restore the stable version at any time
- **Zero extra dependencies**: only APIG + FunctionGraph + VPC; no database or message queue
- **Pipeline friendly**: `src/scripts/promote-canary.sh` provides a "verify → promote" orchestration entry

---

## 5. Involved Cloud Services

| Service | Purpose | Notes |
|---|---|---|
| Application and Website Services (APIG) | API gateway entry, environment and release management | Dedicated instance, BASIC edition |
| FunctionGraph | Stable / candidate business functions | Node.js18.15, 128MB |
| Virtual Private Cloud (VPC) | Network for the APIG instance | Includes subnet and security group |

> **Note**: All services can be created with one command through the Terraform in this repository; to clean up, see [Section 10](#10-clean-up-resources).

---

## 6. Prerequisites

| Item | Requirement | Notes |
|---|---|---|
| **Account** | A real-name verified Huawei Cloud account | Personal or enterprise |
| **Permissions** | IAM **Tenant Administrator** or equivalent | To create VPC / APIG / FunctionGraph resources |
| **Region** | Recommended `cn-north-4` | Cross-region availability may vary |
| **Terraform** | `>= 1.5.0` | IaC deployment tool |
| **huaweicloud Provider** | `>= 1.97.0` | Huawei Cloud Terraform Provider |
| **obsutil** *(optional)* | `>= 5.5.0` | OBS bucket operations (as needed) |
| **kubectl** *(optional)* | `>= 1.28` | K8s cluster management (as needed) |
| **Credentials** | Create Access Key ID and Secret Access Key in "My Credentials" and expose them via the runtime environment | **Do not** write credentials into any code or config file |

---

## 7. Quick Start

### One-command Deployment (Recommended)

```bash
# 1. Clone this repository
git clone <repo-https-url> deterministic-operations-api-canary-deployment
cd deterministic-operations-api-canary-deployment

# 2. Prepare credentials (see [Prerequisites §6](#6-prerequisites))
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"

# 3. Deploy with one command
cd infra
terraform init
terraform plan
terraform apply -auto-approve
```

> **Deployment time**: about 5-10 minutes (depending on resource count).
> **Full steps and expected output**: see [Section 8](#8-step-by-step-deployment).

---

## 8. Step-by-step Deployment

### Step 1: Initialize Working Directory

```bash
cd deterministic-operations-api-canary-deployment/infra
terraform init
```

**Expected output**: `Terraform has been successfully initialized!`

### Step 2: Preview Resource Changes

```bash
terraform plan
```

**Expected output**: `Plan: N to add, 0 to change, 0 to destroy.`

### Step 3: Execute Deployment

```bash
terraform apply -auto-approve
```

**Expected output**: `Apply complete! Resources: N added, 0 changed, 0 destroyed.`

### Step 4: Capture Key Outputs

```bash
terraform output
```

**Expected output**: all output fields (`prod_api_url`, `onepod_api_url`) — keep them for verification.

---

## 9. Usage / Verification

> **Mandatory verification**: the commands / examples in this section were actually executed and verified by the agent before delivery; they run and produce the described output. Verify them yourself and confirm the business function works before considering delivery complete.

### Verify 1: Stable function (verified)

```bash
# Invoke the stable function (FunctionGraph sync call)
hcloud FunctionGraph InvokeFunction --cli-region=cn-north-4 --function_urn="<hello-prod-urn>:latest" --body="{}"
```

**Expected output**:
```
{"statusCode":200,"body":"{\"message\":\"Hello from PROD!\",\"env\":\"prod\",...}"}
```

### Verify 2: Candidate function (verified)

```bash
# Invoke the candidate function (distinct output from stable)
hcloud FunctionGraph InvokeFunction --cli-region=cn-north-4 --function_urn="<hello-canary-urn>:latest" --body="{}"
```

**Expected output**:
```
{"statusCode":200,"body":"{\"message\":\"Hello from CANARY!\",\"env\":\"onepod\",...}"}
```

### Verify 3: Canary promotion (verified)

```bash
# Promote the candidate: rebuild the prod API backend pointing to the candidate function
terraform taint huaweicloud_apig_api.hello_prod
terraform apply -var="promote_canary=true" -auto-approve
# The prod API backend function_urn now points to ...:hello-canary (visible via console / API)
```

**Expected result**: apply rebuilds the prod API; the published backend URN becomes `...:function:default:<project>-hello-canary`.

### Verify 4: Rollback (verified)

```bash
# Restore the stable backend
terraform taint huaweicloud_apig_api.hello_prod
terraform apply -var="promote_canary=false" -auto-approve
# Backend function_urn restores to ...:hello-prod
```

**Expected result**: the prod API backend restores to `...:hello-prod`; the whole flow is reversible.

> **Public API call (requires external network)**: after deployment you can also call the gateway public address:
> `curl -k https://<api-group-subdomain>/prod/hello` or `curl -k https://<api-group-subdomain>/onepod/hello`
> When the verification network cannot resolve the APIG public subdomain, Verifies 1–4 (function invoke + backend switch) serve as the equivalent assertions.

## 10. Clean Up Resources

```bash
# Enter the deployment directory
cd deterministic-operations-api-canary-deployment/infra

# Release all resources in one command
terraform destroy -auto-approve
```

**Expected output**: `Destroy complete! Resources: N destroyed.`

> **Avoid resource leftovers**:
> - `terraform destroy` only releases resources tracked in the Terraform state;
> - Resources created directly via APIs during the process (e.g., manually uploaded OBS objects, manually created EIPs) must be released manually;
> - Shared resources (NAT / VPC shared by other tasks in the account) are not affected.

---

## 11. Detailed Explanation

### Workflow

1. First deployment: create the two function versions, the APIG instance and the `onepod` / `prod` environments; publish the candidate API to `onepod` and the stable API to `prod`
2. Gray observation: call the `onepod` environment endpoint to validate the candidate (no production traffic)
3. Canary promotion: after validation, run `terraform apply -var="promote_canary=true"`; the prod environment API backend switches to the candidate function
4. Rollback: apply with `promote_canary` set to `false` to restore the stable function

### Configuration

| Variable | Default | Description |
|---|---|---|
| `region` | `cn-north-4` | Huawei Cloud region |
| `project_name` | `canary-demo` | Resource name prefix |
| `promote_canary` | `false` | Promotion flag: when `true`, the prod environment API backend points to the candidate function |

### API

| Environment | Method / Path | Description |
|---|---|---|
| `onepod` environment | `GET /hello` | Candidate version (returns `Hello from CANARY!`) |
| `prod` environment | `GET /hello` | Stable version (returns `Hello from PROD!` before promotion) |

Request / response example:

```bash
curl -k https://<prod_api_url>/hello
# {"message":"Hello from PROD!","env":"prod","timestamp":"..."}
```

---

## 12. Dependencies

### Main Dependencies

| Name | Version | Purpose |
|---|---|---|
| Terraform | `>= 1.5.0` | IaC orchestration |
| huaweicloud Provider | `>= 1.97.0` | Huawei Cloud resources |
| Node.js | `18.15` | FunctionGraph runtime |

---

## 13. FAQ / Troubleshooting

### Q1: "Permission denied" during deployment?

**A**: Make sure the account has IAM **Tenant Administrator** or at least the sub-service admin permissions `VPC Administrator`, `APIG Administrator`, `FunctionGraph Administrator`.

### Q2: API returns 404 after `terraform apply`?

**A**: The APIG dedicated instance takes a few minutes to become ready; wait until the instance status is `Running` before calling. Also confirm the API is published to the target environment (this repository auto-publishes via `apig_api_publishment`).

### Q3: How to restore the stable version after promotion?

**A**: Run `terraform apply -var="promote_canary=false" -auto-approve`; the prod environment API backend restores to the stable function.

### Troubleshooting Checklist

| Symptom | Possible Cause | How to Check |
|---|---|---|
| plan fails with auth error | credentials not configured or expired | Re-run `export HW_ACCESS_KEY/HW_SECRET_KEY` and retry |
| API 404 | APIG instance not ready or API not published | Wait for Running; check `terraform output` URLs |
| No change after promotion | `promote_canary` not applied | Confirm apply used `-var="promote_canary=true"` |

---

## 14. Contribution Guide

Welcome Issues and PRs. Please follow this flow:

1. **Issue**: describe the problem / suggestion (with repro commands, expected / actual output, screenshots)
2. **PR**: create a feature branch from `main`; run `terraform validate` and `terraform fmt -check` before submitting
3. **Code Review**: reviewed and merged by **[@<github-username>](https://github.com/<github-username>)**

See `CONTRIBUTING.md` for details (if present).

---

## 15. License

This practice is released under the **MIT No Attribution** license. See the [`LICENSE`](LICENSE) file in the repository root.

```
MIT No Attribution

Copyright (c) Huawei Cloud

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software... (no attribution required)
```

---

## 16. Contact / Maintainers

| Item | Content |
|---|---|
| **Creator** | [@<github-username>](https://github.com/<github-username>) |
| **Maintainer** | [@<github-username>](https://github.com/<github-username>) |
| **Contact** | GitHub Issues / PR (see [Section 14](#14-contribution-guide)) |

---
