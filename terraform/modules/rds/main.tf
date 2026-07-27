# RDS Postgres — not in-cluster, so it survives `terraform destroy` of the
# rest of the stack if you split this into its own state later (today it's
# applied as part of the same `live` root as everything else).

terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "postgres" {
  name_prefix = "${var.name}-rds-"
  vpc_id      = var.vpc_id
  description = "Allow Postgres access from EKS nodes/pods only."

  ingress {
    description     = "Postgres from the EKS cluster security group"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_cluster_security_group_id, var.eks_node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "random_password" "postgres" {
  length  = 24
  special = false # simplifies embedding in a DATABASE_URL connection string
}

resource "aws_db_instance" "postgres" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb # enables storage autoscaling, still free-tier-friendly at this size

  db_name  = var.database_name
  username = var.master_username
  password = random_password.postgres.result

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  # Encryption at rest, using the default aws/rds KMS key — free, and it
  # can't be enabled in place later (it needs a snapshot + restore), so it
  # has to be right before the first apply.
  storage_encrypted = true

  # Private subnets only, never reachable from the internet — the security
  # group above already restricts ingress to the EKS security groups, this
  # is the belt-and-braces version.
  publicly_accessible = false

  # Portfolio-scope trade-offs: single-AZ (no Multi-AZ standby cost), short
  # backup retention, skip a final snapshot on ad-hoc `terraform destroy`
  # (see live/README.md's note on snapshotting manually before a real teardown).
  multi_az                = false
  backup_retention_period = var.backup_retention_days
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = var.tags
}

# --- Credentials in SSM Parameter Store --------------------------------
# Standard-tier parameters are free (Secrets Manager is ~$0.40/secret/month),
# and SecureString encrypts with the AWS-managed `alias/aws/ssm` key, which
# is also free — only customer-managed KMS keys cost $1/month.
#
# What's given up vs Secrets Manager: built-in automatic rotation, and the
# native RDS "managed master password" integration. Neither is wired up
# here anyway, so this is free money for a demo stack.
#
# Path prefix must match what modules/irsa scopes the external-secrets read
# policy to (`parameter/<secret_name_prefix>/*`) — using var.name here
# instead would put this under /<project>-<env>/, which that wildcard does
# NOT match, and ESO would get AccessDenied on DATABASE_URL only.
resource "aws_ssm_parameter" "database_url" {
  name  = "/${var.secret_name_prefix}/database-url"
  type  = "SecureString"
  value = "postgresql://${var.master_username}:${random_password.postgres.result}@${aws_db_instance.postgres.endpoint}/${var.database_name}"
  tags  = var.tags
}
