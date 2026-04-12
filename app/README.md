# Sample app (React + Go + MySQL)

Minimal three-tier app aligned with the Terraform stack in `../aws/`: **CloudFront + S3** (static UI), **ALB + ASG** (Go API on `APP_PORT`, default **8080**), **RDS MySQL** (`manage_master_user_password` + Secrets Manager).

## Layout

| Path | Role |
|------|------|
| `database/schema.sql` | Creates `items` table + seed rows. |
| `backend/` | Go HTTP server: `GET/POST /api/items`, `GET` health path (default `/health`). |
| `frontend/` | Vite + React; `npm run dev` proxies `/api` to `localhost:8080`. |
| `deploy/backend.service.example` | systemd unit; copy to `/etc/systemd/system/` on EC2. |
| `deploy/windows/*.ps1` | Windows PowerShell: build/publish UI, build API binary, apply schema (see repo **README.md**). |

## Local development

1. **MySQL** running locally (or tunnel to RDS), database created.

   ```powershell
   mysql -h 127.0.0.1 -u root -p -e "CREATE DATABASE appdb;"
   mysql -h 127.0.0.1 -u root -p appdb < database/schema.sql
   ```

2. **Backend** (needs [Go 1.22+](https://go.dev/dl/)):

   ```powershell
   cd app/backend
   go mod tidy
   $env:DB_HOST="127.0.0.1"; $env:DB_USER="root"; $env:DB_PASSWORD="..."; $env:DB_NAME="appdb"; $env:APP_PORT="8080"
   go run .
   ```

3. **Frontend**:

   ```powershell
   cd app/frontend
   npm install
   npm run dev
   ```

   Open the Vite URL (e.g. http://localhost:5173). Leave `VITE_API_URL` unset so `/api` is proxied to the Go server.

## After `terraform apply` (AWS)

Use the **step-by-step guide and PowerShell scripts** in the repository **[README.md](../README.md#deploying-the-sample-app-database-backend-frontend)** (`Apply-DatabaseSchema.ps1`, `Build-Backend.ps1`, `Build-Frontend.ps1`, `Publish-Frontend.ps1` under `deploy/windows/`).

Short manual equivalent:

1. **Schema:** `mysql` against RDS from a host that can reach port **3306** (or run SQL via SSM on an app instance).
2. **Backend:** Linux `amd64` binary at `/opt/app/server`, **`DB_SECRET_ARN`** in `/opt/app/app.env`, **systemd** from `deploy/backend.service.example`.
3. **Frontend:** `VITE_API_URL` = public ALB HTTPS URL at build time; sync **`dist/`** to the Terraform frontend bucket and invalidate CloudFront.

## Health check

Target group health path must match Terraform `health_check_path` / `HEALTH_ENDPOINT` (default **`/health`**). The Go server responds with `200` and body `ok`.

## CORS

The API only reflects `Origin` when it appears in `BACKEND_ALLOWED_ORIGINS` (comma-separated). Include your CloudFront URL (and `http://localhost:5173` for local dev if you ever call the API directly from the browser without the Vite proxy).
