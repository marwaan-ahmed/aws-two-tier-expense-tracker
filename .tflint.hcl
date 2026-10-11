# tflint catches mistakes `terraform validate` can't, such as invalid instance
# types or deprecated syntax. Run from the repo root:
#   tflint --init                                   (once: downloads the AWS plugin)
#   tflint --recursive --config "$(pwd)/.tflint.hcl"

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
