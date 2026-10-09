variable "aws_profile" {
  type        = string
  description = "AWS IAM Identity Center profile; null uses the AWS credential chain"
  default     = null
}
variable "vpc_id" {
  type        = string
  description = "VPC containing the public subnet"
}
variable "public_subnet_id" {
  type        = string
  description = "Public subnet with an active default route to an Internet Gateway"
}
variable "domain_prefix" {
  type        = string
  description = "Unique Cognito Hosted UI domain prefix"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,61}[a-z0-9]$", var.domain_prefix))
    error_message = "Use 4-63 lowercase letters, digits and hyphens, beginning and ending with a letter or digit."
  }
}
variable "instance_type" {
  type    = string
  default = "t3.micro"
  validation {
    condition     = contains(["t3.micro", "t3.small", "t3a.micro", "t3a.small"], var.instance_type)
    error_message = "Use one of the supported x86_64 T3 instance types."
  }
}
