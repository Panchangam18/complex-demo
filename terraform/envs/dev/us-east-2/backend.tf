# Generated by Terragrunt. Sig: nIlQXj57tbuaRZEa
terraform {
  backend "s3" {
    bucket         = "complex-demo-tfstate-jyv43s"
    dynamodb_table = "complex-demo-tfstate-locks"
    encrypt        = true
    key            = "dev/us-east-2/terraform.tfstate"
    region         = "us-east-2"
  }
}
