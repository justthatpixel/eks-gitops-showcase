# Remote state — the bucket here must already exist (see ../bootstrap).
# `key` is fixed since this is the one and only environment's infra —
# single environment, no dev/uat/prod split.
#
# `bucket` is deliberately NOT set here — it's account-specific and
# shouldn't be hardcoded into a public repo. Supply it at init time
# instead:
#
#   echo 'bucket = "your-state-bucket-name"' > backend.hcl   # gitignored
#   terraform init -backend-config=backend.hcl
#
# or inline: terraform init -backend-config="bucket=your-state-bucket-name"

terraform {
  backend "s3" {
    key          = "landing-builder/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true # Terraform 1.11+ native S3 locking — no DynamoDB table
  }
}
