variable "security_token" {
  description = "临时安全令牌（STS；使用长期密钥时留空）"
  type        = string
  default     = ""
  sensitive   = true
}

variable "region" {
  description = "华为云区域"
  type        = string
  default     = "cn-north-4"
}

variable "project_name" {
  description = "项目名称，用于资源命名前缀"
  type        = string
  default     = "canary-demo"
}

variable "promote_canary" {
  description = "是否执行金丝雀提升（true = prod 环境 API 后端指向候选版本）"
  type        = bool
  default     = false
}
