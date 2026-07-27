# Terraform bootstrap

Run this **once, manually, before anything else** in `terraform`. It creates the S3 bucket that `../live` uses as its remote state backend.

```sh
cd terraform/bootstrap
terraform init
terraform apply -var="state_bucket_name=landing-builder-tfstate-<your-unique-suffix>"
```

Then, in `../live`, point Terraform at that bucket without hardcoding it into a committed file:

```sh
cd ../live
echo 'bucket = "<the bucket name from the output above>"' > backend.hcl   # gitignored
terraform init -backend-config=backend.hcl
```

## Why this is separate from `live/`

The state bucket can't hold the state that describes its own creation — that's a chicken-and-egg problem. So this config's state stays **local** (a `terraform.tfstate` file next to these `.tf` files, already gitignored). Everything else in `terraform` (the actual VPC/EKS/RDS/S3/ECR stack) stores its state *in* the bucket this config creates.

Because of that, treat this directory differently from `live/`:
- Don't run it repeatedly or fold it into CI — it's a one-time step per AWS account/project.
- The bucket has `force_destroy = true` in `main.tf` — a plain `terraform destroy` here takes it (and every version of every state file in it) with it. Only run it after `live/` is already destroyed.
- Back up or don't lose the local `terraform.tfstate` here — if it's gone, re-import the existing bucket (`terraform import aws_s3_bucket.terraform_state <bucket-name>`) rather than re-applying, since the bucket already exists in AWS.
