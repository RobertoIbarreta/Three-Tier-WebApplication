# Three-Tier Web Application (Terraform)

Infrastructure-as-code for a **three-tier** web application on **AWS** (primary focus) and **GCP** (scaffolded inputs). The goal is a production-style layout: separated concerns, multiple environments, remote state, and clear naming and tagging.

## What This Repository Contains

| Area | Status |
|------|--------|
| **AWS root module** (`aws/`) | Core Terraform files: provider, variables, locals (naming/tags), outputs, empty `main.tf` ready for modules |
| **AWS environments** | `dev`, `stage`, `prod` via per-environment `*.tfvars.example` files (non-overlapping VPC CIDRs when sharing one account) |
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
│   │   ├── dev/dev.tfvars.example
│   │   ├── stage/stage.tfvars.example
│   │   └── prod/prod.tfvars.example
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

- **Do not commit** real `*.tfvars` files; they are **gitignored**.
- **Do commit** `*.tfvars.example` files as templates.
- Keep **`.terraform.lock.hcl`** committed for reproducible provider versions (under `aws/` and `aws/bootstrap/`).

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
4. Note the outputs (`state_bucket_name`, `dynamodb_table_name`, `aws_region`, `backend_config_hint`) for wiring the **main** `aws/` backend (next step in your roadmap).

## AWS: Main Stack (Current Usage)

The main module has **no resources** in `main.tf` yet; you can still validate configuration:

```powershell
cd aws
terraform init -backend=false
terraform validate
```

When you add modules and optional **S3 backend** to `aws/`, plan and apply per environment, for example:

```powershell
cd aws
terraform plan -var-file=environments/dev/dev.tfvars
```

Copy each `*.tfvars.example` to a matching `*.tfvars` in the same folder and set `owner` and other values locally.

## GCP

The `gcp/` directory currently holds **example variable values** only. A full Terraform root (providers, backend, modules) can be added later to mirror the AWS structure.

## Roadmap (Typical Next Steps)

1. Add `backend "s3" { ... }` to the main `aws/` stack using bootstrap outputs; use a **different state `key` per environment** (e.g. `envs/dev/terraform.tfstate`).
2. Implement `aws/modules/network` (VPC, subnets, routing, NAT).
3. Add security groups, RDS, app tier (launch template + ASG), ALB, and outputs.

## License

Specify your license here if the repository is public or shared.
