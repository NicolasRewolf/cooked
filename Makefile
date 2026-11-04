# Contrat unique humain / CI / agent.
# `make check` = les gates PR qui tournent sans secret prod.
# `make check-prod` = T-12 (DATABASE_URL_RO requis).
# Python local = .venv (Homebrew refuse pip système). CI n'utilise pas ce fichier.

PYTHON := .venv/bin/python
DENO  ?= deno
NPM   ?= npm

.PHONY: help deps lint test check check-prod test-sql test-python test-paths test-docs test-tracker test-edge test-dashboard

.DEFAULT_GOAL := help

help:
	@echo "make check       — lint + tous les tests locaux (sans secret prod)"
	@echo "make lint        — ruff (src/, scripts/, tests/)"
	@echo "make test        — mêmes suites que la CI PR, hors prod-drift"
	@echo "make check-prod  — drift du socle (DATABASE_URL ou DATABASE_URL_RO)"
	@echo "make deps        — crée .venv et installe le paquet cooked + outils de check"

$(PYTHON):
	python3 -m venv .venv
	$(PYTHON) -m pip install -q -e ".[dev]"

deps: $(PYTHON)
	$(PYTHON) -m pip install -q -e ".[dev]"

lint: $(PYTHON)
	$(PYTHON) -m ruff check src scripts tests

test: test-sql test-python test-paths test-docs test-tracker test-edge test-dashboard

check: lint test

test-sql: $(PYTHON)
	# Hors CI le script scanne tout l'historique (C6 échoue). Même mode que GitHub : diff vs origin/main.
	GITHUB_ACTIONS=1 $(PYTHON) scripts/check_migration_paris_date.py
	$(PYTHON) scripts/check_rpcs_sql_fresh.py
	$(PYTHON) scripts/check_schema_migrations.py
	$(NPM) ci --prefix tests/sql
	$(NPM) test --prefix tests/sql

test-python: $(PYTHON)
	$(PYTHON) -m pytest

test-paths:
	@command -v $(DENO) >/dev/null || { echo "manque deno — brew install deno (CI : denoland/setup-deno@v2)"; exit 1; }
	$(DENO) test supabase/functions/_shared/canonical_path_test.ts

test-docs: $(PYTHON)
	$(PYTHON) scripts/check_docs_constants.py

test-tracker: $(PYTHON)
	$(PYTHON) scripts/minify-tracker.py
	@if grep -nE 'COOKED_DEBUG[[:space:]]*=[[:space:]]*true' wix/*.js; then \
		echo "COOKED_DEBUG = true dans un fichier Velo"; exit 1; \
	fi
	$(NPM) ci --prefix tests
	$(NPM) test --prefix tests

test-edge:
	@command -v $(DENO) >/dev/null || { echo "manque deno — brew install deno (CI : denoland/setup-deno@v2)"; exit 1; }
	$(DENO) test supabase/functions/_shared/events_row_test.ts
	$(DENO) test supabase/functions/_shared/track_row_test.ts
	$(DENO) test supabase/functions/_shared/track_delivery_test.ts
	$(DENO) check supabase/functions/track/index.ts
	$(DENO) test supabase/functions/_shared/form_row_test.ts
	$(DENO) test supabase/functions/_shared/form_delivery_test.ts
	$(DENO) check supabase/functions/form-webhook/index.ts
	$(DENO) test supabase/functions/_shared/ingest_gate_test.ts
	$(DENO) test supabase/functions/_shared/ingest_drops_test.ts

test-dashboard:
	$(NPM) ci --prefix dashboard
	$(NPM) run lint --prefix dashboard
	$(NPM) test --prefix dashboard
	NEXT_PUBLIC_SUPABASE_URL=https://example.supabase.co \
	NEXT_PUBLIC_SUPABASE_ANON_KEY=synthetic-public-key \
	DASHBOARD_ALLOWED_EMAILS=synthetic@example.invalid $(NPM) run build --prefix dashboard

check-prod: $(PYTHON)
	@set -e; url="$${DATABASE_URL_RO:-$$DATABASE_URL}"; \
	if [ -z "$$url" ]; then \
		echo "DATABASE_URL_RO (ou DATABASE_URL) requis — rôle cooked_ci_ro, lecture seule."; \
		exit 1; \
	fi; \
	DATABASE_URL="$$url" $(PYTHON) scripts/check_prod_drift.py
