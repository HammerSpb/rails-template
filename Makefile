.PHONY: help setup registry-up registry-down registry-logs \
        deploy-production deploy-staging \
        logs-production logs-staging \
        console-production console-staging \
        ssh-production ssh-staging \
        db-backup-production db-backup-staging \
        lint lint-fix \
        local-certs \
        clean

help:  ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2}'

setup:  ## Bootstrap: install deps, prepare DB, start local registry
	bin/setup

registry-up:  ## Start local Docker registry (localhost:5555)
	docker compose -f docker-compose.registry.yml up -d

registry-down:  ## Stop local Docker registry
	docker compose -f docker-compose.registry.yml down

registry-logs:  ## Tail local registry logs
	docker compose -f docker-compose.registry.yml logs -f

deploy-production:  ## Deploy to production via Kamal
	bin/kamal deploy

deploy-staging:  ## Deploy to staging via Kamal
	bin/kamal deploy -d staging

logs-production:  ## Tail production app logs
	bin/kamal logs

logs-staging:  ## Tail staging app logs
	bin/kamal logs -d staging

console-production:  ## Rails console against production
	bin/kamal console

console-staging:  ## Rails console against staging
	bin/kamal console -d staging

ssh-production:  ## Shell into production app container
	bin/kamal shell

ssh-staging:  ## Shell into staging app container
	bin/kamal shell -d staging

db-backup-production:  ## pg_dump production -> backups/
	bin/db-backup production

db-backup-staging:  ## pg_dump staging -> backups/
	bin/db-backup staging

lint:  ## Run RuboCop + ERB Lint
	bin/rubocop
	bundle exec erb_lint --lint-all

lint-fix:  ## Run RuboCop + ERB Lint with autocorrect
	bin/rubocop -a
	bundle exec erb_lint --lint-all --autocorrect

local-certs:  ## Generate mkcert TLS certs for *.local hosts
	bin/generate-local-certs

clean:  ## Remove backups and local certs
	rm -rf backups .kamal/certs
