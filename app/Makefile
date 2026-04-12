# Unix-friendly shortcuts (use Git Bash or WSL on Windows).

.PHONY: backend-tidy backend-linux frontend-build

backend-tidy:
	cd backend && go mod tidy && go vet ./...

backend-linux:
	cd backend && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o server .

frontend-build:
	cd frontend && npm ci && npm run build
