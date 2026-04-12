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
| **Sample app** (`app/`) | React (Vite) UI, Go API, MySQL `schema.sql`—deploy steps in [`app/README.md`](app/README.md) |

The **`aws/`** stack defines VPC, ALB, ASG, RDS, CloudFront, and related services. Use **`app/`** to build the UI and API, then install artifacts on AWS as described in `app/README.md`.

## Repository Layout

```text
Three-Tier-WebApplication/
├── README.md                 # This file
├── .gitignore                # Terraform state, .terraform/, *.tfvars (examples allowed)
├── docs/                     # Extra documentation (see docs/README.md)
├── app/                      # Sample React + Go + SQL app (deploy onto aws/)
│   ├── deploy/windows/       # PowerShell: build & publish scripts
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

To **build and publish the sample app** from Windows you also need:

- [Go 1.22+](https://go.dev/dl/) (backend)
- [Node.js LTS](https://nodejs.org/) / `npm` (frontend)
- Optional: **MySQL/MariaDB client** (`mysql` on PATH) if you run [`Apply-DatabaseSchema.ps1`](app/deploy/windows/Apply-DatabaseSchema.ps1) from your PC (RDS is private; see below)

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

## Deploying the sample app (database, backend, frontend)

The sample UI and API live under [`app/`](app/). Terraform provisions **RDS MySQL**, **ALB + ASG** (API on `app_port`, default **8080**), **S3 + CloudFront** (static site), and writes **`/opt/app/app.env`** on new instances (`APP_PORT`, `HEALTH_ENDPOINT`, `BACKEND_ALLOWED_ORIGINS`). You still **ship the binary**, **apply SQL**, and **upload static files**.

### 0. Apply infrastructure and capture outputs

From `aws/` (same workspace you will use for outputs):

```powershell
cd aws
terraform apply -var-file=environments\dev\dev.tfvars
terraform output -raw alb_https_endpoint
terraform output -raw frontend_cloudfront_url
terraform output -raw frontend_s3_bucket_name
terraform output -raw frontend_cloudfront_distribution_id
terraform output -raw db_master_user_secret_arn
```

Set **`backend_allowed_origins`** in your `*.tfvars` to your **CloudFront URL** (e.g. `https://d111111abcdef8.cloudfront.net`) so the Go API allows browser `Origin` headers. Include `http://localhost:5173` only if you call the API from the browser during local UI dev without the Vite proxy. Re-apply after changing it.

### 1. Database (`app/database/schema.sql`)

Creates the `items` table and seed rows. **RDS has no public endpoint** in the default stack, so choose one approach:

- **From your PC:** temporarily allow your IP on the **RDS security group** (or use a VPN into the VPC), ensure **`mysql`** and **AWS CLI** work, then run:

  ```powershell
  cd <repo-root>
  .\app\deploy\windows\Apply-DatabaseSchema.ps1
  ```

  The script reads `db_master_user_secret_arn` via `terraform output` and loads credentials from Secrets Manager.

- **From an app EC2 instance:** open **Session Manager**, install `mysql` if needed (`sudo yum install -y mariadb1011-client` or similar), upload `app/database/schema.sql`, then:

  ```bash
  mysql -h <rds_address> -u <user> -p <dbname> < schema.sql
  ```

  Use the master user and password from the RDS secret in Secrets Manager if you are not using IAM DB auth.

### 2. Backend (Go on EC2)

1. Build a **Linux amd64** binary on Windows:

   ```powershell
   cd <repo-root>
   .\app\deploy\windows\Build-Backend.ps1
   ```

   This writes `app\backend\server` (no extension).

2. Copy **`server`** to **`/opt/app/server`** on **each** instance (ASG may replace instances—automate with Golden AMI, CI, or S3 + user-data later).

   Practical options: **Session Manager** file transfer, **`aws s3 cp`** to a bucket your instance role can read (add IAM if you introduce a “releases” bucket), or **SCP** if you use key-based SSH.

3. On the instance, append **`DB_SECRET_ARN`** to **`/opt/app/app.env`** (value = `terraform output -raw db_master_user_secret_arn`). The instance role already has **`secretsmanager:GetSecretValue`** for that ARN ([`aws/secrets_iam.tf`](aws/secrets_iam.tf)).

4. Install the systemd unit and start the API:

   ```bash
   sudo cp /path/to/backend.service.example /etc/systemd/system/backend.service
   # Edit if needed: WorkingDirectory=/opt/app, EnvironmentFile=/opt/app/app.env, ExecStart=/opt/app/server
   sudo chmod +x /opt/app/server
   sudo systemctl daemon-reload
   sudo systemctl enable --now backend.service
   ```

   Template: [`app/deploy/backend.service.example`](app/deploy/backend.service.example).

5. Confirm the target group sees **healthy** targets: **`GET https://<alb-dns>/health`** should return `200` and body `ok`.

### 3. Frontend (React → S3 + CloudFront)

1. Build with the **public API base URL** (ALB HTTPS, no trailing slash):

   ```powershell
   cd <repo-root>
   .\app\deploy\windows\Build-Frontend.ps1 -ApiBaseUrl "https://<your-alb-dns>.<region>.elb.amazonaws.com"
   ```

2. Upload **`app/frontend/dist`** and invalidate CloudFront (reads bucket and distribution ID from **terraform output** in `aws/`):

   ```powershell
   .\app\deploy\windows\Publish-Frontend.ps1
   ```

   Or pass values explicitly: `.\Publish-Frontend.ps1 -Bucket "..." -DistributionId "E..." -Region "us-east-1"`.

3. Open **`terraform output -raw frontend_cloudfront_url`** (or your custom domain if configured).

### PowerShell scripts (summary)

| Script | Purpose |
|--------|---------|
| [`app/deploy/windows/Apply-DatabaseSchema.ps1`](app/deploy/windows/Apply-DatabaseSchema.ps1) | Apply `schema.sql` using Secrets Manager + `mysql` (needs network path to RDS). |
| [`app/deploy/windows/Build-Backend.ps1`](app/deploy/windows/Build-Backend.ps1) | Cross-compile Go API to `app/backend/server` for Linux. |
| [`app/deploy/windows/Build-Frontend.ps1`](app/deploy/windows/Build-Frontend.ps1) | `npm run build` with `-ApiBaseUrl` → `app/frontend/dist`. |
| [`app/deploy/windows/Publish-Frontend.ps1`](app/deploy/windows/Publish-Frontend.ps1) | `aws s3 sync` + CloudFront invalidation `/*`. |

All scripts assume the repository layout is intact and you run them from any directory (they resolve paths from `$PSScriptRoot`). Terraform commands run in **`aws/`** using your **current backend and workspace**.

More detail and local dev: [`app/README.md`](app/README.md).

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

1. Harden app delivery: bake the Go binary into an AMI or pull from S3 in **user-data**, add health checks and rollouts.
2. Automate **`backend_allowed_origins`** and **`VITE_API_URL`** per environment (fixed ALB DNS or Route53 `api_dns_name`).
3. Wire CI/CD: `terraform plan` / `apply`, then `Build-*` / `Publish-Frontend.ps1` (or Linux equivalents) with OIDC or deployment roles.

## License

Specify your license here if the repository is public or shared.
