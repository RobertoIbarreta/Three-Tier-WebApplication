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

## AWS Infrastructure (Full 3-Tier Description)

This stack provisions a production-style **3-tier web architecture** on AWS:

- **Presentation tier:** CloudFront + private S3 origin for static frontend hosting
- **Application tier:** Public ALB + private EC2 Auto Scaling Group
- **Data tier:** Private RDS in dedicated DB subnets
- **Cross-cutting controls:** IAM least-privilege, optional WAF, backup, monitoring, and optional Route53 aliases

### 1) Network and Subnet Topology

The stack creates a dedicated VPC with DNS support and DNS hostnames enabled, plus three subnet tiers across configured AZs:

- **Public subnets**
  - Host the Application Load Balancer
  - Route `0.0.0.0/0` to an Internet Gateway
  - Host one NAT Gateway per public subnet/AZ for app-tier egress
- **Private app subnets**
  - Host EC2 app instances (no public IPs)
  - Route outbound traffic through NAT Gateways
  - Optionally host interface endpoints for `ssm`, `ssmmessages`, and `ec2messages`
- **Private DB subnets**
  - Used by the RDS DB subnet group
  - Isolated from direct internet ingress

### 2) Security Model

Security is enforced with SG boundaries and IAM:

- **ALB SG:** allows inbound `80/443` from internet (IPv4 and optional IPv6)
- **App SG:** allows inbound app port traffic only from ALB SG
- **DB SG:** allows inbound DB port traffic only from App SG
- **EC2 IAM role:** includes Session Manager access and scoped Secrets Manager/KMS permissions for the RDS master secret

This design keeps only the load-balancing entrypoint internet-facing while application and data tiers remain private.

### 3) Application Tier (Compute + Load Balancing)

- **Launch template**
  - Uses latest Amazon Linux 2 AMI from SSM public parameters
  - Attaches app instance profile and app SG
  - Writes `/opt/app/app.env` with `APP_PORT`, `HEALTH_ENDPOINT`, and `BACKEND_ALLOWED_ORIGINS`
- **Auto Scaling Group**
  - Spans private app subnets
  - Uses configurable `min/desired/max` capacity
  - Registers instances in ALB target group and uses ELB health checks
- **ALB listeners**
  - HTTP listener can redirect to HTTPS (`enable_http_to_https_redirect`) or forward directly
  - HTTPS listener terminates TLS with ACM certificate (`acm_certificate_arn`)
- **Scaling policy**
  - Target tracking on `ALBRequestCountPerTarget`

### 4) Presentation Tier (S3 + CloudFront)

- **Frontend S3 bucket**
  - Private, versioned, and locked down with block public access
  - Ownership mode `BucketOwnerEnforced`
  - Lifecycle policy to expire noncurrent versions after a configurable number of days
- **CloudFront distribution**
  - Uses Origin Access Control (OAC) with SigV4 for private S3 access
  - Redirects viewers to HTTPS
  - Supports SPA fallback by mapping `403/404` to `index.html` (configurable error document)
  - Supports optional custom domain with ACM cert in `us-east-1`
- **Bucket policy**
  - Grants `s3:GetObject` only to the specific CloudFront distribution ARN

### 5) Data Tier (RDS)

- **RDS deployment**
  - Provisioned in private DB subnets using DB subnet group
  - Not publicly accessible
  - Engine/version/class/storage are variable-driven
  - Optional Multi-AZ and backup retention controls
- **Encryption**
  - Dedicated KMS key and alias for RDS at-rest encryption
- **Credentials**
  - `manage_master_user_password = true`
  - RDS manages master password in Secrets Manager
  - Sensitive secret ARN is output as `db_master_user_secret_arn`
  - App EC2 role can read only that secret and decrypt with constrained KMS permissions

### 6) WAF (Optional)

When `enable_waf = true`, a regional WAFv2 Web ACL is attached to the ALB with AWS managed rule groups:

- `AWSManagedRulesCommonRuleSet`
- `AWSManagedRulesKnownBadInputsRuleSet`
- `AWSManagedRulesSQLiRuleSet`

Optional overrides let selected managed rules run in `COUNT` mode for tuning.

### 7) Monitoring and Logging

- **ALB access logs (optional):**
  - Dedicated S3 bucket with SSE-S3 encryption, public access block, and lifecycle retention
  - Correct bucket policy for ELB log delivery principals
- **CloudWatch alarms (optional and configurable):**
  - ALB unhealthy hosts
  - ALB target `5xx` responses
  - ALB target response time
  - RDS CPU utilization
  - RDS free storage space
  - RDS database connections
- **SNS integration:** alarm and OK actions can be routed to configured SNS topic ARNs

### 8) Backup and DR (Optional)

When `enable_aws_backup = true`, the stack creates:

- Primary backup vault
- Backup IAM role + managed policy attachments
- Daily backup plan and lifecycle retention
- Backup selection for RDS (and optionally frontend S3)

When `enable_backup_cross_region_copy = true`, recovery points are copied to a DR-region vault using the provider alias `aws.dr`.

### 9) Route53 Integration (Optional)

If `route53_zone_id` is supplied:

- `api_dns_name` creates an alias `A` record to the ALB
- `frontend_domain_name` creates alias `A/AAAA` records to CloudFront

This expects an existing public hosted zone and manages alias records only.

### 10) Naming, Tags, and Outputs

- **Naming convention:** `<project>-<environment>-<component>`
- **Default tags:** `Project`, `Environment`, `ManagedBy=Terraform`, `Owner`
- **Useful outputs include:** VPC/subnet IDs, ALB endpoint, ASG/LT IDs, CloudFront URL, frontend bucket name, DB endpoint, and optional WAF/backup/Route53 outputs

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
