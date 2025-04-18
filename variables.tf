# Define custom variables here if needed
variable "my_ip" {
  type        = string
  description = "Your public IP in CIDR format, e.g., [\"203.0.113.25/32\"]"
}

variable "db_password" {
  type        = string
  description = "The password for the RDS instance"
  sensitive   = true
}

variable "profile_default" {
  type = string
}
