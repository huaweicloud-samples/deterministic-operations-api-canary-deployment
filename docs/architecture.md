# 架构说明

`deterministic-operations-api-canary-deployment` 提供一套「API 金丝雀发布」参考实践：同一 API 同时部署**稳定版本**与**候选版本**两个后端，分别发布到独立环境，验证候选版本通过后执行「提升」动作，使其成为稳定后端。该模式用于降低发布风险、支持灰度观测与快速回滚。

## 架构图

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

## 核心组件

| 组件 | 说明 |
|---|---|
| APIG 专享实例 | API 网关入口，承载 API 定义、环境与发布 |
| 发布环境 `onepod` | 候选版本发布环境，用于灰度观测（发布候选 API） |
| 发布环境 `prod` | 稳定版本发布环境，承载线上流量 |
| FunctionGraph `hello-canary` | 候选版本业务函数（验证期返回候选标识） |
| FunctionGraph `hello-prod` | 稳定版本业务函数（返回稳定标识） |
| 金丝雀提升开关 | `promote_canary` 变量：apply 时切换 prod 环境 API 后端指向候选函数 |

## 发布流程

1. 首次部署：创建两版本函数、APIG 实例与两个发布环境，候选 API 发布到 `onepod`、稳定 API 发布到 `prod`
2. 灰度观测：调用 `onepod` 环境地址验证候选版本（返回候选标识，不影响线上）
3. 提升：验证通过后以 `promote_canary=true` 再次 apply，prod 环境 API 后端切换为候选函数
4. 回滚：将 `promote_canary` 置回 `false` 应用，prod 环境 API 后端恢复原始稳定函数

## 设计说明

- 双版本后端通过**两个发布环境**隔离，候选版本不参与线上流量，规避「边改边发布」风险
- 「提升」由发布参数显式控制，动作幂等、可回滚，适合接入发布流水线（执行 `promote-canary.sh` 触发）
- 本实践不含认证/鉴权、数据库与消息总线，聚焦发布控制面，可与任意业务后端组合