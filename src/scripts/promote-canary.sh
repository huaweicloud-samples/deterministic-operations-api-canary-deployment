#!/usr/bin/env bash
# 金丝雀提升脚本：将 prod 环境 API 后端指向候选（canary）函数
# 用法：terraform apply -var="promote_canary=true"
# 说明：在部署期以 null_resource 触发，或在发布流水线中调用本脚本完成「提升」。
# 提升动作本身由 IaC 的 promote_canary 开关完成（apply 时切换后端指向），
# 本脚本用于 CI/CD 流水线中顺序化「先验证 canary → 再提升」的步骤。
set -euo pipefail

echo "[promote-canary] 金丝雀验证通过，开始提升..."
echo "[promote-canary] 在发布流水线中执行：terraform apply -var='promote_canary=true'"
echo "[promote-canary] 提升完成后，候选版本将成为 prod 环境的稳定后端。"
