package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	_ "github.com/go-sql-driver/mysql"
)

// RDS master-user secret shape from Secrets Manager (manage_master_user_password).
type rdsSecret struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Host     string `json:"host"`
	Port     int    `json:"port"`
	DBName   string `json:"dbname"`
}

type item struct {
	ID        uint64    `json:"id"`
	Title     string    `json:"title"`
	CreatedAt time.Time `json:"created_at"`
}

type createBody struct {
	Title string `json:"title"`
}

func main() {
	port := getenv("APP_PORT", "8080")
	healthPath := getenv("HEALTH_ENDPOINT", "/health")
	allowed := parseOrigins(getenv("BACKEND_ALLOWED_ORIGINS", ""))

	dsn, err := buildDSN(context.Background())
	if err != nil {
		log.Fatalf("database config: %v", err)
	}

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		log.Fatalf("mysql open: %v", err)
	}
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(4)
	defer db.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	if err := db.PingContext(ctx); err != nil {
		cancel()
		log.Fatalf("mysql ping: %v", err)
	}
	cancel()

	mux := http.NewServeMux()
	mux.HandleFunc(healthPath, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("/api/items", func(w http.ResponseWriter, r *http.Request) {
		if !cors(w, r, allowed) {
			return
		}
		switch r.Method {
		case http.MethodGet:
			listItems(w, r, db)
		case http.MethodPost:
			createItem(w, r, db)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	})

	addr := ":" + port
	log.Printf("listening on %s (health %s)", addr, healthPath)
	log.Fatal(http.ListenAndServe(addr, mux))
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func parseOrigins(s string) []string {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func cors(w http.ResponseWriter, r *http.Request, allowed []string) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	ok := false
	for _, o := range allowed {
		if o == origin {
			ok = true
			break
		}
	}
	if !ok {
		w.WriteHeader(http.StatusForbidden)
		return false
	}
	w.Header().Set("Access-Control-Allow-Origin", origin)
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return false
	}
	return true
}

func buildDSN(ctx context.Context) (string, error) {
	secretARN := os.Getenv("DB_SECRET_ARN")
	if secretARN != "" {
		cfg, err := config.LoadDefaultConfig(ctx)
		if err != nil {
			return "", err
		}
		sm := secretsmanager.NewFromConfig(cfg)
		out, err := sm.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{SecretId: aws.String(secretARN)})
		if err != nil {
			return "", fmt.Errorf("GetSecretValue: %w", err)
		}
		var sec rdsSecret
		if err := json.Unmarshal([]byte(aws.ToString(out.SecretString)), &sec); err != nil {
			return "", fmt.Errorf("secret json: %w", err)
		}
		if sec.Port == 0 {
			sec.Port = 3306
		}
		// tls=skip-verify keeps the sample deploy simple; pin RDS CA in production.
		return fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?parseTime=true&tls=skip-verify",
			sec.Username, sec.Password, sec.Host, sec.Port, sec.DBName), nil
	}

	host := os.Getenv("DB_HOST")
	user := os.Getenv("DB_USER")
	pass := os.Getenv("DB_PASSWORD")
	name := os.Getenv("DB_NAME")
	p := getenv("DB_PORT", "3306")
	if host == "" || user == "" || name == "" {
		return "", fmt.Errorf("set DB_SECRET_ARN (on EC2) or DB_HOST, DB_USER, DB_PASSWORD, DB_NAME for local/dev")
	}
	return fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true&tls=skip-verify", user, pass, host, p, name), nil
}

func listItems(w http.ResponseWriter, r *http.Request, db *sql.DB) {
	rows, err := db.QueryContext(r.Context(), `SELECT id, title, created_at FROM items ORDER BY id ASC`)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var list []item
	for rows.Next() {
		var it item
		if err := rows.Scan(&it.ID, &it.Title, &it.CreatedAt); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		list = append(list, it)
	}
	if list == nil {
		list = []item{}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(list)
}

func createItem(w http.ResponseWriter, r *http.Request, db *sql.DB) {
	var body createBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	body.Title = strings.TrimSpace(body.Title)
	if body.Title == "" {
		http.Error(w, "title required", http.StatusBadRequest)
		return
	}
	res, err := db.ExecContext(r.Context(), `INSERT INTO items (title) VALUES (?)`, body.Title)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	id, _ := res.LastInsertId()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(map[string]any{"id": id, "title": body.Title})
}
