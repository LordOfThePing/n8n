# Makefile for the n8n + Cloudflare Tunnel + MongoDB stack (deploy/)
#
# Usage (run on the server, from this folder):
#   make up        # build/pull images and start services detached
#   make down      # stop and remove containers
#   make logs      # tail combined logs (service: make logs c=<service>)
#   make status    # docker compose ps
#   make restart   # restart all services
#   make rebuild   # stop, rebuild images, start again
#   make pull      # pull the referenced images from the registry
#
# All targets use deploy/.env if present; otherwise they pass no env-file.

ENV_FILE := $(if $(wildcard .env),--env-file .env,)
SVC ?=

.PHONY: up down logs status restart rebuild pull help

up: ## Start services detached
	@test -f .env || (echo "ERROR: deploy/.env missing (copy .env.example -> .env)" >&2; exit 1)
	docker compose $(ENV_FILE) up -d $(SVC)

down: ## Stop and remove containers
	docker compose $(ENV_FILE) down $(SVC)

logs: ## Tail combined logs (make logs c=<service>)
	docker compose $(ENV_FILE) logs -f --tail=100 $(SVC)

status: ## Show container status
	docker compose $(ENV_FILE) ps $(SVC)

restart: ## Restart all services
	docker compose $(ENV_FILE) restart $(SVC)

pull: ## Pull the referenced images
	docker compose $(ENV_FILE) pull $(SVC)

rebuild: ## Stop, rebuild images, and start again
	@test -f .env || (echo "ERROR: deploy/.env missing (copy .env.example -> .env)" >&2; exit 1)
	docker compose $(ENV_FILE) down $(SVC)
	docker compose $(ENV_FILE) build --no-cache $(SVC)
	docker compose $(ENV_FILE) up -d $(SVC)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'
