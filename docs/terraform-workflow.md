# Terraform Workflow

This document defines baseline safety and team workflow rules for Terraform in this repository.

## Core Safety Rules

1. Run checks in this order before any apply:
   - `terraform fmt -recursive`
   - `terraform validate`
   - `terraform plan`
2. Use environment-specific tfvars files (for example, `environments/dev/dev.tfvars`).
3. Never commit real `.tfvars` files; commit only `*.tfvars.example` templates.
4. Review Terraform plan output in pull requests before running `terraform apply`.
5. Keep `.terraform.lock.hcl` committed unless team policy explicitly says otherwise.

## Standard Local Workflow

Run from the Terraform root (for example, `aws/`):

```powershell
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform plan -var-file=environments/dev/dev.tfvars
```

When using remote backend for an environment:

```powershell
terraform init -backend-config=environments/dev/backend.hcl -reconfigure
terraform plan -var-file=environments/dev/dev.tfvars
```

## Environment Discipline

- Always pair matching files for the same environment:
  - backend config: `environments/<env>/backend.hcl`
  - variables: `environments/<env>/<env>.tfvars`
- Do not mix environment files (for example, prod backend with dev tfvars).
- Re-run `terraform init -reconfigure` when switching environments.

## Pull Request Requirements

- Include the environment used for planning (`dev`, `stage`, or `prod`).
- Include a Terraform plan summary in the PR description or discussion.
- Ensure no secrets or real `.tfvars` files are in the diff.
- If `.terraform.lock.hcl` changes, include it in the commit and review provider updates.

## Apply Policy

- Do not run `terraform apply` until plan review is complete.
- Prefer controlled applies (maintainer or CI-driven) for shared environments.
