variable "aws_region" {
  type        = string
  description = "Target AWS Region"
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Project Identifier"
  default     = "cloud-app"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public Subnet CIDRs"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance size"
}

variable "instance_count" {
  type        = number
  description = "Total number of instances"
}

variable "enable_alb" {
  type        = bool
  description = "Deploy Application Load Balancer for high availability"
}