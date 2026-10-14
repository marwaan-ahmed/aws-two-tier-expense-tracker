terraform {
  backend "s3" {
    bucket       = "expense-tracker-tfstate-941167138759"
    key          = "terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
