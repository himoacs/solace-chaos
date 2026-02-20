# Terraform backend configuration (optional - for remote state)

# Uncomment and configure for remote state storage
# terraform {
#   backend "s3" {
#     bucket = "your-terraform-state-bucket"
#     key    = "solace-chaos/terraform.tfstate"
#     region = "us-east-1"
#   }
# }

# Or use local backend (default)
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}