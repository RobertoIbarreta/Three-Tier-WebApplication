# Three-Tier Web Application (Terraform)

Infrastructure-as-code for a **three-tier** web application on **AWS** (primary focus) and **GCP** (scaffolded inputs). The goal is a production-style layout: separated concerns, multiple environments, remote state, and clear naming and tagging.

## What This Repository Contains

| Area | Status |
|------|--------|
| **AWS root module** (`aws/`) | Core Terraform files; **partial S3 backend** (configure at `terraform init` via `backend.hcl` per environment) |
| **AWS environments** | `dev` / `stage` / `prod`: `*.tfvars.example` + `backend.hcl.example` (separate state **key** per env: `envs/<env>/terraform.tfstate`) |
| **AWS bootstrap** (`aws/bootstrap/`) | Dedicated stack that creates **S3** (remote state) + **DynamoDB** (state locking) |
| **AWS modules** (`aws/modules/`) | Placeholder folders: `network`, `security`, `app`, `db` (to be implemented) |
| **GCP** (`gcp/`) | Example `prod.tfvars.example` only; no full Terraform root yet |

Application resources (VPC, ALB, ASG, RDS, and so on) are **not** defined yet in the main `aws/` stack; this repo documents the **foundation** you built so far.

## Repository Layout

```text
Three-Tier-WebApplication/
├── README.md                 # This file
├── .gitignore                # Terraform state, .terraform/, *.tfvars (examples allowed)
├── docs/                     # Extra documentation (see docs/README.md)
├── aws/                      # Main AWS Terraform root
│   ├── main.tf               # Compose modules here
│   ├── versions.tf
│   ├── providers.tf          # AWS provider + default_tags from locals
│   ├── variables.tf
│   ├── locals.tf             # name_prefix + common_tags
│   ├── outputs.tf
│   ├── environments/
│   │   ├── dev/   (dev.tfvars.example, backend.hcl.example)
│   │   ├── stage/ (stage.tfvars.example, backend.hcl.example)
│   │   └── prod/  (prod.tfvars.example, backend.hcl.example)
│   ├── modules/              # network, security, app, db (stubs)
│   └── bootstrap/          # One-time (per account/region) state backend
│       ├── main.tf           # S3 bucket + DynamoDB lock table
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
└── gcp/
    └── prod.tfvars.example   # Placeholder variables for future GCP stack
```

## Naming and Tagging (AWS)

- **Resource names:** `<project>-<environment>-<component>` (e.g. `three-tier-webapp-prod-vpc`).  
  Use `local.name_prefix` (`<project>-<environment>`) and append `-<component>` per resource.
- **Default tags** (via provider `default_tags`): `Project`, `Environment`, `ManagedBy = Terraform`, `Owner` (from variable `owner`).

`environment` is restricted to `dev`, `stage`, or `prod`. `project_name` must be lowercase alphanumeric with hyphens.

## Secrets and Git

- **Do not commit** real `*.tfvars` or per-environment **`backend.hcl`** (account-specific bucket/table); they are **gitignored**.
- **Do commit** `*.tfvars.example` and `backend.hcl.example` as templates.
- Keep **`.terraform.lock.hcl`** committed for reproducible provider versions (under `aws/` and `aws/bootstrap/`).

### RDS master credentials (Secrets Manager)

The AWS root module sets `manage_master_user_password = true` on [`aws_db_instance.main`](aws/main.tf). RDS creates and rotates the master password in **AWS Secrets Manager**; Terraform **must not** copy that password into SSM Parameter Store (avoids drift and fights rotation).

- **Operators:** after apply, read the sensitive output `db_master_user_secret_arn` from [`aws/outputs.tf`](aws/outputs.tf) (e.g. `terraform output -raw db_master_user_secret_arn`).
- **App tier (EC2):** the application instance role [`aws_iam_role.app_ec2`](aws/main.tf) includes an inline policy ([`aws/secrets_iam.tf`](aws/secrets_iam.tf)) allowing `secretsmanager:GetSecretValue` on **that secret ARN only** and `kms:Decrypt` on the secret’s CMK with `kms:ViaService` scoped to Secrets Manager. At runtime the app should call `GetSecretValue`, parse the **JSON** secret string, and use the fields AWS documents for RDS master secrets (including **host**, **port**, **username**, **password**, and DB identifier fields as provided). Wiring that into application code is outside this repo unless you add it explicitly.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) `>= 1.5.0`
- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials for the target account
- An AWS account (and a **globally unique** S3 bucket name for bootstrap)

## AWS: Bootstrap (Remote State Backend)

Bootstrap creates **only** the infrastructure Terraform needs to store state safely:

- **S3 bucket** — versioning, encryption, public access blocked, deny insecure transport
- **DynamoDB table** — lock table with `LockID` attribute for Terraform state locking

Bootstrap uses **local state** by default so you are not depending on the bucket before it exists.

1. `cd aws/bootstrap`
2. Copy `terraform.tfvars.example` to `terraform.tfvars` (ignored by git) and set `state_bucket_name` to a **unique** name.
3. Run `terraform init`, `terraform plan`, `terraform apply`.
4. Note the outputs (`state_bucket_name`, `dynamodb_table_name`, `aws_region`, `backend_config_hint`) for wiring the **main** `aws/` backend.

## AWS: Main Stack — Remote State (S3 + DynamoDB)

The main stack uses a **partial** `backend "s3" {}` in [`aws/versions.tf`](aws/versions.tf). Terraform does not allow variables inside `backend` blocks, so **bucket, key, region, DynamoDB table, and encryption** are supplied at init time.

Per environment, copy `environments/<env>/backend.hcl.example` → `backend.hcl` and set:

- **`bucket`** — bootstrap output `state_bucket_name`
- **`key`** — `envs/dev/terraform.tfstate`, `envs/stage/terraform.tfstate`, or `envs/prod/terraform.tfstate` (one object per environment)
- **`region`** — same region as the bucket
- **`dynamodb_table`** — bootstrap output `dynamodb_table_name`
- **`encrypt`** — `true` (SSE for state in S3)

Initialize (pick **one** environment per working copy, or re-init with `-reconfigure` when switching):

```powershell
cd aws
terraform init -backend-config=environments/prod/backend.hcl
```

If you previously used **local** state in `aws/` and want to **upload** it to S3, use:

```powershell
terraform init -backend-config=environments/prod/backend.hcl -migrate-state
```

Validate without configuring the backend (CI or quick checks):

```powershell
cd aws
terraform init -backend=false
terraform validate
```

Plan and apply (after init **with** the correct backend for that environment):

```powershell
cd aws
terraform plan -var-file=environments/prod/prod.tfvars
```

Copy each `*.tfvars.example` to a matching `*.tfvars` in the same folder and set `owner` and other values locally.

The main module still has **no application resources** in `main.tf` yet; remote state is ready for when you add them.

## Scaffold Validation Status

Readiness checks were completed for `dev` before starting network/app/db implementation.

- **Backend lock acquisition (DynamoDB):** Passed  
  Confirmed via Terraform output showing `Acquiring state lock` and `Releasing state lock` during plan/apply operations.
- **State object written to expected S3 key:** Passed  
  Verified object exists at `envs/dev/terraform.tfstate` in the remote state bucket.
- **Provider versions pinned and reproducible:** Passed  
  `aws/versions.tf` constrains AWS provider (`~> 5.0`) and `aws/.terraform.lock.hcl` pins exact provider checksums/version for teammate consistency.
- **Example tfvars present and non-sensitive:** Passed  
  `dev/stage/prod` `*.tfvars.example` files exist and contain sample placeholders (no secrets committed).

Validation commands used:

```powershell
cd aws
terraform init -backend-config=environments/dev/backend.hcl -reconfigure
terraform plan -var-file=environments/dev/dev.tfvars -lock-timeout=60s
terraform apply -refresh-only -auto-approve -var-file=environments/dev/dev.tfvars
```

## GCP

The `gcp/` directory currently holds **example variable values** only. A full Terraform root (providers, backend, modules) can be added later to mirror the AWS structure.

## Roadmap (Typical Next Steps)

1. Implement `aws/modules/network` (VPC, subnets, routing, NAT).
2. Add security groups, RDS, app tier (launch template + ASG), ALB, and outputs.
3. Wire CI/CD to run `terraform plan` per environment with the matching `backend.hcl` and `*.tfvars`.

## License

Specify your license here if the repository is public or shared.
