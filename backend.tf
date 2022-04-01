# data "terraform_remote_state" "local" {
#   backend = "local"
#
#   config = {
#     path = "terraform.tfstate"
#   }
# }

# terraform {
#   backend "s3" {
#     region  = "ap-southeast-1"
#     encrypt = true
#   }
# }
