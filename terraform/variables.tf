variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for RKE2 nodes"
  type        = string
  default     = "t3.medium"
}

variable "ubuntu_ami" {
  description = "Ubuntu 22.04 LTS AMI in us-east-1 (ami-0c7217cdde317cfec is official Canonical)"
  type        = string
  default     = "ami-0c7217cdde317cfec"
}
