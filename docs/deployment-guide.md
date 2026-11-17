# 部署指导书

本指导书说明如何在华为云部署 `deterministic-operations-api-canary-deployment`，完成「候选版本发布 → 灰度观测 → 提升」的完整演示。

## 1. 前置条件

- 华为云账号（已实名认证），区域 `cn-north-4`
- 本地已安装 Terraform（≥ 1.5）与华为云 Provider 对应 CLI（可选）
- 在「我的凭证」页面创建 Access Key / Secret Key
- 账号需具备 APIG、FunctionGraph、VPC 相关操作权限

## 2. 准备

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# 编辑 terraform.tfvars，填写 region 与 project_name
```

将访问密钥配置到运行时环境（不写入任何文件）：

```bash
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"
```

## 3. 部署

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

apply 完成后输出两个地址：

- `onepod_api_url` —— 候选版本（onepod 环境）API 地址
- `prod_api_url` —— 稳定版本（prod 环境）API 地址

## 4. 验证金丝雀发布

### 4.1 验证稳定版本

```bash
curl -k https://<prod_api_url>/hello
# 期望：{"message":"Hello from PROD!","env":"prod",...}
```

### 4.2 验证候选版本（不干扰线上）

```bash
curl -k https://<onepod_api_url>/hello
# 期望：{"message":"Hello from CANARY!","env":"onepod",...}
```

### 4.3 金丝雀提升

候选版本验证通过后，执行提升：

```bash
terraform apply -var="promote_canary=true" -auto-approve
curl -k https://<prod_api_url>/hello
# 期望：prod 环境后端已切换，返回候选版本输出（Hello from CANARY!）
```

### 4.4 回滚

若候选版本存在问题，恢复稳定后端：

```bash
terraform apply -var="promote_canary=false" -auto-approve
curl -k https://<prod_api_url>/hello
# 期望：恢复 Hello from PROD!
```

## 5. 清理资源

```bash
terraform destroy -auto-approve
```

释放 APIG 实例、FunctionGraph 函数、VPC 等全部资源，避免残留。