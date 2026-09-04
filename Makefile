# Contrat unique humain / CI / agent.
# `make check` = les gates PR qui tournent sans secret prod.
# `make check-prod` = T-12 (DATABASE_URL_RO requis).
# Python local = .venv (Homebrew refuse pip système). CI n'utilise pas ce fichier.

PYTHON := .venv/bin/python
DENO  ?= deno
NODE  ?= node
NPM   ?= npm

.PHONY: help deps lint test check check-prod test-sql test-python test-paths test-docs test-tracker test-edge test-dashboard

.DEFAULT_GOAL := help

help:
	@echo "make check       — lint + tous les tests locaux (sans secret prod)"
	@echo "make lint        — ruff (src/, scripts/, tests/)"
	@echo "make test        — mêmes suites que la CI PR, hors prod-drift"
	@echo "make check-prod  — T-12 / I12 / T-13 (DATABASE_URL ou DATABASE_URL_RO)"
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

test-python: $(PYTHON)
	$(PYTHON) -m pytest \
		tests/test_gsc_common.py \
		tests/test_dfs_common.py \
		tests/test_cooked_store.py \
		tests/test_wix_taxonomy_sync.py \
		tests/test_secib_ingest.py \
		tests/test_wix_forms_import.py \
		tests/test_gbp_ingest.py \
		-q
	$(PYTHON) scripts/check_normalize_vectors.py

test-paths: $(PYTHON)
	$(PYTHON) -m pytest tests/test_canonical_path_contract.py -q
	@command -v $(DENO) >/dev/null || { echo "manque deno — brew install deno (CI : denoland/setup-deno@v2)"; exit 1; }
	$(DENO) test supabase/functions/_shared/canonical_path_test.ts

test-docs: $(PYTHON)
	$(PYTHON) scripts/check_docs_constants.py

test-tracker: $(PYTHON)
	$(PYTHON) scripts/minify-tracker.py
	@if grep -nE 'COOKED_DEBUG[[:space:]]*=[[:space:]]*true' wix/*.js; then \
		echo "COOKED_DEBUG = true dans un fichier Velo"; exit 1; \
	fi
	@test -d node_modules/jsdom || npm install jsdom --no-save
	$(NODE) tests/tracker.test.js

test-edge:
	@command -v $(DENO) >/dev/null || { echo "manque deno — brew install deno (CI : denoland/setup-deno@v2)"; exit 1; }
	$(DENO) test supabase/functions/_shared/events_row_test.ts
	$(DENO) test supabase/functions/_shared/track_row_test.ts
	$(DENO) test supabase/functions/_shared/form_row_test.ts
	$(DENO) test supabase/functions/_shared/ingest_gate_test.ts
	$(DENO) test supabase/functions/_shared/ingest_drops_test.ts

test-dashboard:
	@test -d dashboard/node_modules || (cd dashboard && $(NPM) ci)
	cd dashboard && $(NPM) test

check-prod: $(PYTHON)
	@url="$${DATABASE_URL_RO:-$$DATABASE_URL}"; \
	if [ -z "$$url" ]; then \
		echo "DATABASE_URL_RO (ou DATABASE_URL) requis — rôle cooked_ci_ro, lecture seule."; \
		exit 1; \
	fi; \
	DATABASE_URL="$$url" $(PYTHON) scripts/check_prod_drift.py; \
	DATABASE_URL="$$url" $(PYTHON) scripts/check_normalize_vectors.py; \
	DATABASE_URL="$$url" $(PYTHON) scripts/generate_dashboard_contracts.py --check
