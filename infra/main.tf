# ============================================================================
# API 金丝雀发布实践（华为云 APIG + FunctionGraph）
# ============================================================================
# 架构语义：API 网关金丝雀（Canary）发布
#   - prod 环境：稳定版本 API（hello-prod 函数）
#   - onepod 环境：候选版本 API（hello-canary 函数）
#   - 验证候选版本后，通过 promote 脚本把 prod 环境 API 后端指向候选函数（提升）
# 即：一次部署两个版本，灰度观测后自动提升。
# ============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.70"
    }
  }
}

# 访问密钥由运行时环境提供，仓内不保存任何凭据值。
provider "huaweicloud" {
  region         = var.region
  security_token = var.security_token
}

# ============================================================================
# Layer 1: 网络
# ============================================================================

resource "huaweicloud_vpc" "main" {
  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"
}

resource "huaweicloud_vpc_subnet" "main" {
  name       = "${var.project_name}-subnet"
  vpc_id     = huaweicloud_vpc.main.id
  cidr       = "10.0.1.0/24"
  gateway_ip = "10.0.1.1"
}

resource "huaweicloud_networking_secgroup" "main" {
  name        = "${var.project_name}-sg"
  description = "Security group for ${var.project_name}"
}

# ============================================================================
# Layer 2: 计算（FunctionGraph）
# ============================================================================

# 稳定版本函数（PROD）
resource "huaweicloud_fgs_function" "hello_prod" {
  name        = "${var.project_name}-hello-prod"
  app         = "default"
  handler     = "index.handler"
  memory_size = 128
  timeout     = 30
  runtime     = "Node.js18.15"
  code_type   = "inline"
  func_code   = filebase64("../src/functions/hello-prod/index.js")
}

# 候选版本函数（CANARY / OnePod）
resource "huaweicloud_fgs_function" "hello_canary" {
  name        = "${var.project_name}-hello-canary"
  app         = "default"
  handler     = "index.handler"
  memory_size = 128
  timeout     = 30
  runtime     = "Node.js18.15"
  code_type   = "inline"
  func_code   = filebase64("../src/functions/hello-canary/index.js")
}

# ============================================================================
# Layer 3: API 接入（APIG 专享实例 + 双环境发布）
# ============================================================================

data "huaweicloud_availability_zones" "main" {}

resource "huaweicloud_vpc_eip" "apig" {
  publicip { type = "5_bgp" }
  bandwidth {
    name        = "${var.project_name}-apig-eip"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "huaweicloud_apig_instance" "main" {
  name              = "${var.project_name}-apig"
  eip_id            = huaweicloud_vpc_eip.apig.id
  edition           = "BASIC"
  vpc_id            = huaweicloud_vpc.main.id
  subnet_id         = huaweicloud_vpc_subnet.main.id
  security_group_id = huaweicloud_networking_secgroup.main.id
  available_zones   = [data.huaweicloud_availability_zones.main.names[0]]
}

resource "huaweicloud_apig_group" "main" {
  name        = "${var.project_name}-group"
  instance_id = huaweicloud_apig_instance.main.id
  description = "API group for ${var.project_name}"
}

# 发布环境：onepod（候选版本）与 prod（稳定版本）
# 候选版本独立分组（APIG 同一分组内 path+method 唯一，双版本用分组隔离）
resource "huaweicloud_apig_group" "canary" {
  name        = "${var.project_name}-group-canary"
  instance_id = huaweicloud_apig_instance.main.id
  description = "Canary candidate API group"
}

resource "huaweicloud_apig_environment" "onepod" {
  name        = "onepod"
  instance_id = huaweicloud_apig_instance.main.id
  description = "Canary candidate environment"
}

resource "huaweicloud_apig_environment" "prod" {
  name        = "prod"
  instance_id = huaweicloud_apig_instance.main.id
  description = "Production environment"
}

# GET /hello：候选版本 API（发布到 onepod 环境）
resource "huaweicloud_apig_api" "hello_canary" {
  name             = "hello-canary"
  group_id         = huaweicloud_apig_group.canary.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "GET"
  request_path     = "/hello"
  request_protocol = "HTTPS"

  func_graph {
    function_urn     = replace(huaweicloud_fgs_function.hello_canary.urn, ":latest", "")
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
  }
}

# GET /hello：稳定版本 API（发布到 prod 环境）
resource "huaweicloud_apig_api" "hello_prod" {
  name             = "hello-prod"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "GET"
  request_path     = "/hello"
  request_protocol = "HTTPS"

  func_graph {
    # 提升开关：promote_canary=true 时 prod 环境 API 后端指向候选函数（即「金丝雀提升」）
    function_urn     = var.promote_canary ? replace(huaweicloud_fgs_function.hello_canary.urn, ":latest", "") : replace(huaweicloud_fgs_function.hello_prod.urn, ":latest", "")
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
  }
}

# API 发布到环境（API 必须发布后才能访问）
resource "huaweicloud_apig_api_publishment" "onepod" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.hello_canary.id
  env_id      = huaweicloud_apig_environment.onepod.id
}

resource "huaweicloud_apig_api_publishment" "prod" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.hello_prod.id
  env_id      = huaweicloud_apig_environment.prod.id
}

# ============================================================================
# 金丝雀提升（Promote）：对应一次「候选版本提升」动作
# ============================================================================
# 验证候选版本无问题后，执行一次提升：
#   1) 手动/流水线触发：terraform apply -var="promote_canary=true"
#   2) 提升动作 = 把 prod 环境 API 后端从稳定函数切到候选函数
# 本示例用「提升开关」表达该自动化（部署期 null_resource 执行脚本亦可替代，
# 见 src/scripts/promote-canary.sh）。
# ============================================================================

output "prod_api_url" {
  description = "稳定版本（prod 环境）API 地址"
  value       = "https://${huaweicloud_apig_instance.main.ingress_address}/${huaweicloud_apig_environment.prod.name}"
}

output "onepod_api_url" {
  description = "候选版本（onepod 环境）API 地址"
  value       = "https://${huaweicloud_apig_instance.main.ingress_address}/${huaweicloud_apig_environment.onepod.name}"
}