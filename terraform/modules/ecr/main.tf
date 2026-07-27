# One ECR repo per deployable service (frontend, backend). Nodes pull via
# their IAM role — no image pull secrets, no Docker Hub rate limits.

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "${var.name_prefix}/${each.value}"
  image_tag_mutability = "IMMUTABLE" # tags are git SHAs — never meant to be overwritten

  # Demo stack: `terraform destroy` should succeed even with real images
  # pushed. ECR refuses to delete a non-empty repository otherwise.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# Keep a short image history per repo — this is a demo cluster, not an
# artifact archive. Untagged/old images are pruned so ECR storage cost
# stays near zero.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the last ${var.keep_last_n_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_n_images
        }
        action = { type = "expire" }
      }
    ]
  })
}
