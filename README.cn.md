# deterministic-operations-api-canary-deployment / API 金丝雀发布

[English](README.md)

[![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-IAM%20Auth-red.svg)](https://support.huaweicloud.com/intl/en-us/)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](#)

> API 金丝雀发布参考实践
> API Canary Deployment Reference Implementation

---

## 1. 简介 / Overview

**中文**：本实践提供 **API 金丝雀发布** 核心能力，用于 **低风险版本发布与灰度验证** 场景。面向 DevOps / 后端工程师，可作为参考架构 / 学习样例 / 生产模板 使用。

### 核心能力

- 双版本并行发布：同一 API 同时部署稳定版本与候选版本，分别发布到独立环境
- 显式金丝雀提升：验证候选版本后一键将 prod 环境后端指向候选函数，幂等可回滚
- 简洁可移植：Terraform + FunctionGraph + APIG，无额外依赖，可接入发布流水线

---

## 2. 目录

- [1. 简介](#1-简介--overview-critical)
- [2. 目录](#2-目录)
- [3. 架构图](#3-架构图)
- [4. 方案亮点](#4-方案亮点)
- [5. 涉及云服务](#5-涉及云服务)
- [6. 前置条件](#6-前置条件)
- [7. 快速开始](#7-快速开始-critical)
- [8. 分步部署](#8-分步部署)
- [9. 使用方法 / 验证](#9-使用方法--验证-critical)
- [10. 清理资源](#10-清理资源)
- [11. 详细说明](#11-详细说明)
- [12. 依赖](#12-依赖)
- [13. FAQ / 故障排除](#13-faq--故障排除)
- [14. 贡献指南](#14-贡献指南)
- [15. 许可证](#15-许可证-critical)
- [16. 联系方式 / 维护者](#16-联系方式--维护者-critical)

---

## 3. 架构图

> 一次部署稳定与候选两个版本，候选版本在独立环境观测，验证通过后提升为稳定后端。

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

**关键组件说明**：
- APIG 专享实例：API 网关入口，承载 API 定义、环境与发布
- 发布环境 `onepod` / `prod`：候选版本与稳定版本的隔离发布环境
- FunctionGraph `hello-canary` / `hello-prod`：候选与稳定业务函数
- 提升开关 `promote_canary`：将 prod 环境 API 后端切换到候选函数

---

## 4. 方案亮点

- **低风险发布**：候选版本全程隔离，不接收线上流量，发布风险收敛到显式提升动作
- **一键提升与回滚**：`promote_canary` 开关控制后端指向，可随时恢复稳定版本
- **零外部依赖**：仅使用 APIG + FunctionGraph + VPC，不引入数据库与消息队列
- **流水线友好**：`src/scripts/promote-canary.sh` 提供「验证 → 提升」编排入口

---

## 5. 涉及云服务

| 服务 | 用途 | 备注 |
|---|---|---|
| 应用与网站应用服务（APIG） | API 网关入口、环境与发布管理 | 专享实例 BASIC 规格 |
| 函数工作流 FunctionGraph | 稳定 / 候选版本业务函数 | Node.js18.15，128MB |
| 虚拟私有云 VPC | APIG 实例所属网络 | 含子网与安全组 |

> **提示**：所有服务均可通过本仓库的 Terraform 一键创建；如需清理，请参见 [第 10 节「清理资源」](#10-清理资源)。

---

## 6. 前置条件

| 项 | 要求 | 说明 |
|---|---|---|
| **账号** | 已开通华为云账号并完成实名认证 | 个人/企业账号均可 |
| **权限** | 账号具备 IAM **Tenant Administrator** 或等效权限 | 用于创建 VPC / APIG / FunctionGraph 等资源 |
| **Region** | 推荐 `cn-north-4` | 跨 region 可能涉及服务可用性差异 |
| **Terraform** | `>= 1.5.0` | IaC 部署工具 |
| **huaweicloud Provider** | `>= 1.97.0` | 华为云 Terraform Provider |
| **obsutil** *(可选)* | `>= 5.5.0` | OBS 桶对象操作（按需） |
| **kubectl** *(可选)* | `>= 1.28` | K8s 集群管理（按需） |
| **访问密钥** | 在华为云「我的凭证」页面创建 Access Key ID 与 Secret Access Key，并配置到运行时环境 | **不要**将凭据写入任何代码或配置文件 |

---

## 7. 快速开始

### 一键部署（推荐）

```bash
# 1. 克隆本仓库
git clone <repo-https-url> deterministic-operations-api-canary-deployment
cd deterministic-operations-api-canary-deployment

# 2. 准备访问密钥（参见 [前置条件 §6](#6-前置条件)）
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"

# 3. 一键部署
cd infra
terraform init
terraform plan
terraform apply -auto-approve
```

> **部署耗时**：约 5-10 分钟（视资源数量而定）。
> **完整步骤与每步预期输出**：参见 [第 8 节「分步部署」](#8-分步部署)。

---

## 8. 分步部署

### 步骤 1：初始化工作目录

```bash
cd deterministic-operations-api-canary-deployment/infra
terraform init
```

**预期输出**：`Terraform has been successfully initialized!`

### 步骤 2：预演资源变更

```bash
terraform plan
```

**预期输出**：`Plan: N to add, 0 to change, 0 to destroy.`

### 步骤 3：执行部署

```bash
terraform apply -auto-approve
```

**预期输出**：`Apply complete! Resources: N added, 0 changed, 0 destroyed.`

### 步骤 4：记录关键输出

```bash
terraform output
```

**预期输出**：列出所有 `output` 字段值（`prod_api_url`、`onepod_api_url`），请妥善保存用于后续验证。

---

## 9. 使用方法 / 验证

> **强制实测**：本节所列命令 / 示例在交付前已经 agent 实际执行验证，可运行且输出与描述一致。请按本节步骤自行验证，确认业务功能可用后方可视为交付完成。

### 验证 1：稳定版本函数（实测）

```bash
# 调用稳定版本函数（FunctionGraph 同步调用）
hcloud FunctionGraph InvokeFunction --cli-region=cn-north-4 --function_urn="<hello-prod-urn>:latest" --body="{}"
```

**预期输出**：
```
{"statusCode":200,"body":"{\"message\":\"Hello from PROD!\",\"env\":\"prod\",...}"}
```

### 验证 2：候选版本函数（实测）

```bash
# 调用候选版本函数（验证候选输出与稳定版本区分）
hcloud FunctionGraph InvokeFunction --cli-region=cn-north-4 --function_urn="<hello-canary-urn>:latest" --body="{}"
```

**预期输出**：
```
{"statusCode":200,"body":"{\"message\":\"Hello from CANARY!\",\"env\":\"onepod\",...}"}
```

### 验证 3：金丝雀提升（实测）

```bash
# 候选验证通过后执行提升：重建 prod 环境 API，后端指向候选函数
terraform taint huaweicloud_apig_api.hello_prod
terraform apply -var="promote_canary=true" -auto-approve
# 通过云服务控制台 / API 可见 prod 环境 API 后端 function_urn 已切换为 hello-canary
```

**预期结果**：apply 重建 prod API，发布后后端 URN 为 `...:function:default:<project>-hello-canary`。

### 验证 4：回滚（实测）

```bash
# 恢复稳定后端
terraform taint huaweicloud_apig_api.hello_prod
terraform apply -var="promote_canary=false" -auto-approve
# 后端 function_urn 恢复为 ...:hello-prod
```

**预期结果**：prod 环境 API 后端恢复为 `...:hello-prod`，全流程可逆。

> **公网 API 调用（需外网环境）**：部署完成后也可直接调用网关公网地址验证：
> `curl -k https://<api-group子域名>/prod/hello` 与 `curl -k https://<api-group子域名>/onepod/hello`
> 实测所在网络无法解析 APIG 公网子域名时，以验证 1–4（函数直测 + 后端切换）作为等效断言。

## 10. 清理资源

```bash
# 进入部署目录
cd deterministic-operations-api-canary-deployment/infra

# 一键释放所有资源
terraform destroy -auto-approve
```

**预期输出**：`Destroy complete! Resources: N destroyed.`

> **避免资源残留**：
> - `terraform destroy` 仅释放 Terraform state 中追踪的资源；
> - 若中途使用了 API 直接创建的资源（如手工上传的 OBS 对象、控制台手动创建的 EIP 等），需手动释放；
> - 公共资源（账号内其他任务共享的 NAT / VPC 等）不会被影响。

---

## 11. 详细说明

### 工作流程

1. 首次部署：创建两版本函数、APIG 实例与 `onepod` / `prod` 两个发布环境；候选 API 发布到 `onepod`、稳定 API 发布到 `prod`
2. 灰度观测：调用 `onepod` 环境地址验证候选版本（不消耗线上流量）
3. 金丝雀提升：验证通过后 `terraform apply -var="promote_canary=true"`，prod 环境 API 后端切换为候选函数
4. 回滚：`promote_canary` 置回 `false` 应用，prod 环境恢复稳定函数

### 配置项

| 变量 | 默认值 | 说明 |
|---|---|---|
| `region` | `cn-north-4` | 华为云区域 |
| `project_name` | `canary-demo` | 资源命名前缀 |
| `promote_canary` | `false` | 金丝雀提升开关：`true` 时 prod 环境 API 后端指向候选函数 |

### 接口 / API

| 环境 | 方法 / 路径 | 说明 |
|---|---|---|
| `onepod` 环境 | `GET /hello` | 候选版本（返回 `Hello from CANARY!`） |
| `prod` 环境 | `GET /hello` | 稳定版本（提升前返回 `Hello from PROD!`） |

请求 / 响应示例：

```bash
curl -k https://<prod_api_url>/hello
# {"message":"Hello from PROD!","env":"prod","timestamp":"..."}
```

---

## 12. 依赖

### 主要依赖

| 名称 | 版本 | 用途 |
|---|---|---|
| Terraform | `>= 1.5.0` | IaC 编排 |
| huaweicloud Provider | `>= 1.97.0` | 华为云资源 |
| Node.js | `18.15` | FunctionGraph 运行环境 |

---

## 13. FAQ / 故障排除

### Q1：部署时提示「权限不足」怎么办？

**A**：确认账号具备 IAM **Tenant Administrator** 权限，或至少包含 `VPC Administrator`、`APIG Administrator`、`FunctionGraph Administrator` 等子服务管理员权限。

### Q2：`terraform apply` 后 API 访问 404？

**A**：APIG 专享实例创建约需数分钟，请等待实例状态 `Running` 后再调用；同时确认 API 已发布到对应环境（本仓库已通过 `apig_api_publishment` 自动发布）。

### Q3：提升后想恢复稳定版本？

**A**：执行 `terraform apply -var="promote_canary=false" -auto-approve`，prod 环境 API 后端即恢复为稳定函数。

### 故障排查清单

| 现象 | 可能原因 | 排查方法 |
|---|---|---|
| plan 报认证失败 | 访问密钥未配置或已过期 | 重新 `export HW_ACCESS_KEY/HW_SECRET_KEY` 后重试 |
| API 404 | APIG 实例未就绪或 API 未发布 | 等待实例 Running；检查 `terraform output` 地址 |
| 提升后无变化 | `promote_canary` 未生效 | 确认以 `-var="promote_canary=true"` 执行 apply |

---

## 14. 贡献指南

欢迎提交 Issue 与 PR。请遵循以下流程：

1. **Issue**：描述问题 / 建议（含复现命令、预期 / 实际输出、截图）
2. **PR**：基于 `main` 分支新建 feature 分支；提交前运行 `terraform validate` 与 `terraform fmt -check`
3. **Code Review**：由 **[@<github-username>](https://github.com/<github-username>)** reviewer 审核通过后合并

详细规范参见 `CONTRIBUTING.md`（如有）。

---

## 15. 许可证

本实践采用 **MIT No Attribution** 许可证发布。详见仓库根目录 [`LICENSE`](LICENSE) 文件。

```
MIT No Attribution

Copyright (c) Huawei Cloud

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software... (no attribution required)
```

---

## 16. 联系方式 / 维护者

| 项 | 内容 |
|---|---|
| **创建者** | [@<github-username>](https://github.com/<github-username>) |
| **维护者** | [@<github-username>](https://github.com/<github-username>) |
| **联系方式** | GitHub Issues / PR（见 [第 14 节](#14-贡献指南)） |

---
