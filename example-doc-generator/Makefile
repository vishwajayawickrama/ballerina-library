.PHONY: help setup setup-python setup-bal build run \
        start-agent stop-agent \
        crop-screenshots crop-screenshots-dry crop-screenshots-backup \
        publish-docs publish-docs-dry publish-docs-no-pr \
        batch-commit-docs batch-commit-docs-dry \
        batch-pr-docs batch-pr-docs-dry \
        batch-commit-sample batch-commit-sample-dry \
        batch-pr-samples batch-pr-samples-dry \
        batch-run batch-run-dry pipeline-commit pipeline-commit-dry pipeline-pr pipeline-pr-dry \
        publish-sample publish-sample-dry publish-sample-no-pr publish-sample-no-publish \
        cleanup cleanup-dry \
        clean clean-artifacts

# ── Default ──────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Connector Docs Automation — available targets"
	@echo ""
	@echo "  Setup"
	@echo "    make setup            Install all dependencies (Ballerina + Python)"
	@echo "    make setup-python     Create python/.venv and install Python deps"
	@echo "    make setup-bal        Build the Ballerina project"
	@echo ""
	@echo "  Run"
	@echo "    make run CONNECTOR=mysql                                                     Run the full pipeline for a connector"
	@echo "    make run CONNECTOR=mysql ADDITIONAL_INSTRUCTIONS='...'                       Run with per-connector guidance"
	@echo "    make run TRIGGER=trigger.github                                              Run the full pipeline for a trigger (-t)"
	@echo "    make run TRIGGER=trigger.github PACKAGE=ballerinax/trigger.github            Run trigger mode with explicit package path"
	@echo "    make start-agent      Start the Python agent server in the foreground"
	@echo "    make stop-agent       Send shutdown request to the agent server"
	@echo ""
	@echo "  Publish"
	@echo "    make publish-docs             Publish docs + create PR (auto-detects docs-integrator path)"
	@echo "    make publish-docs-dry         Dry run — print planned actions, no changes"
	@echo "    make publish-docs-no-pr       Push branch + commit only, skip PR creation"
	@echo "    PUBLISH_ARGS='...'            Pass extra flags, e.g. PUBLISH_ARGS='--category security-identity'"
	@echo "    DOCS_REPO=PATH                Override docs-integrator path"
	@echo "    DOCS_UPSTREAM=OWNER/REPO      Override docs PR target repo"
	@echo "    DOCS_BASE_BRANCH=BRANCH       Override docs PR base branch"
	@echo ""
	@echo "  Unified Pipeline"
	@echo "    make batch-run                            Run queue from batch_connectors.json"
	@echo "    make batch-run-dry                        Print planned execution order, no changes"
	@echo "    make pipeline-commit                      Commit current docs + sample to batch branches"
	@echo "    make pipeline-pr                          Create docs + sample PRs from batch branches"
	@echo "    DOCS_BRANCH=<branch>                      Docs batch branch (default: docs/connector-docs)"
	@echo "    SAMPLES_BRANCH=<branch>                   Samples batch branch (default: samples/connector-samples)"
	@echo ""
	@echo "  Batch Docs (commit reviewed docs to one branch, then one PR)"
	@echo "    make batch-commit-docs                   Commit current connector artifacts (default branch: docs/connector-docs)"
	@echo "    make batch-commit-docs BRANCH=<branch>   Commit to a custom branch"
	@echo "    make batch-commit-docs-dry               Dry run"
	@echo "    make batch-pr-docs BRANCH=<branch>       Create one PR from the shared branch"
	@echo "    make batch-pr-docs-dry BRANCH=<branch>   Dry run"
	@echo "    BRANCH=<name>                             Optional for commit (default: docs/connector-docs); required for PR"
	@echo "    CATEGORY=<cat>                            Override auto-detected connector category"
	@echo "    ARTIFACTS_DIR=<path>                      Override artifacts directory"
	@echo "    DOCS_FORK=<owner/repo>                    Override fork slug"
	@echo "    BATCH_COMMIT_DOCS_ARGS=<flags>            Extra flags for pipeline.py commit-docs"
	@echo "    BATCH_PR_DOCS_ARGS=<flags>                Extra flags for pipeline.py pr-docs"
	@echo "    Workflow: review artifacts → 'make batch-commit-docs' for each approved item"
	@echo "              → 'make batch-pr-docs BRANCH=...' once all docs are committed"
	@echo ""
	@echo "  Batch Samples (commit multiple samples to one branch, then one PR)"
	@echo "    make batch-commit-sample                   Commit current sample (default branch: samples/connector-samples)"
	@echo "    make batch-commit-sample BRANCH=<branch>   Commit to a custom branch"
	@echo "    make batch-commit-sample-dry               Dry run"
	@echo "    make batch-pr-samples BRANCH=<branch>      Create one PR from the shared branch"
	@echo "    make batch-pr-samples-dry BRANCH=<branch>  Dry run"
	@echo "    BRANCH=<name>                               Optional for commit (default: samples/connector-samples); required for PR"
	@echo "    BATCH_COMMIT_SAMPLE_ARGS=<flags>            Extra flags for pipeline.py commit-sample"
	@echo "    BATCH_PR_SAMPLES_ARGS=<flags>               Extra flags for pipeline.py pr-samples"
	@echo "    Workflow: review project → 'make batch-commit-sample' for each approved sample"
	@echo "              → 'make batch-pr-samples BRANCH=...' once all samples are committed"
	@echo ""
	@echo "  Batch Run (queue multiple connectors/triggers sequentially)"
	@echo "    BATCH_CONFIG=path.json            Override config file (default: batch_connectors.json)"
	@echo "    BATCH_RUN_ARGS='--no-resume'      Extra flags: --no-resume, --create-prs, --timeout N"
	@echo "    Workflow: 1) make batch-run  2) review artifacts_archive/  3) commit approved items"
	@echo "              4) make pipeline-pr"
	@echo ""
	@echo "  Publish Sample"
	@echo "    make publish-sample               Publish integration sample PR + delete local project + close tabs"
	@echo "    make publish-sample-dry           Dry run — print planned actions, no changes"
	@echo "    make publish-sample-no-pr         Push branch + commit only, skip PR creation"
	@echo "    make publish-sample-no-publish    Delete local project + close tabs, skip sample publishing"
	@echo "    PUBLISH_SAMPLE_ARGS='...'         Pass extra flags to publish_sample.py"
	@echo "    CODE_SERVER_PORT=N                Override code-server port"
	@echo "    SAMPLES_REPO=PATH                 Override integration-samples path"
	@echo "    INTEGRATION_UPSTREAM=OWNER/REPO   Override samples PR target repo"
	@echo "    INTEGRATION_BASE_BRANCH=BRANCH    Override samples PR base branch"
	@echo "    PROJECT_PATH=PATH                 Manually set project path (writes created-project.txt)"
	@echo "    NO_PR=1                           Push branch but skip PR creation"
	@echo ""
	@echo "  Artifacts"
	@echo "    make clean            Remove artifacts/, target/, Dependencies.toml, python/.venv"
	@echo "    make clean-artifacts  Remove only the artifacts/ directory"
	@echo ""

# ── Setup ────────────────────────────────────────────────────────────────────
setup: setup-python setup-bal
	@echo "Setup complete."

# Sentinel file: rebuilt whenever requirements.txt changes or .venv is missing.
python/.venv/.installed: python/requirements.txt
	@echo "→ Creating python/.venv and installing Python dependencies..."
	cd python && uv venv
	cd python && uv pip install -r requirements.txt
	cd python && .venv/bin/playwright install chromium
	touch python/.venv/.installed
	@echo "Python setup complete."

setup-python: python/.venv/.installed
	@echo "Python environment is ready. Activate with: source python/.venv/bin/activate"

setup-bal:
	@echo "→ Building Ballerina project..."
	bal build
	@echo "Ballerina build complete."

# ── Run ──────────────────────────────────────────────────────────────────────

AGENT_SERVER_PORT ?= 8765
ADDITIONAL_INSTRUCTIONS ?=
PACKAGE ?=
export ADDITIONAL_INSTRUCTIONS

run:
	@[ "$(CONNECTOR)$(TRIGGER)" ] || { echo "Usage: make run CONNECTOR=mysql OR make run TRIGGER=trigger.github [PACKAGE=ballerinax/trigger.github]"; exit 1; }
	@if [ -n "$(TRIGGER)" ]; then \
		echo "→ Running full pipeline for trigger: $(TRIGGER)$(if $(PACKAGE), (package: $(PACKAGE)),)$(if $(ADDITIONAL_INSTRUCTIONS), (with additional instructions),)"; \
		bal run -- -t $(TRIGGER) $(if $(PACKAGE),"$(PACKAGE)",) $(if $(ADDITIONAL_INSTRUCTIONS),"$$ADDITIONAL_INSTRUCTIONS",); \
	else \
		echo "→ Running full pipeline for connector: $(CONNECTOR)$(if $(ADDITIONAL_INSTRUCTIONS), (with additional instructions),)"; \
		bal run -- $(CONNECTOR) $(if $(ADDITIONAL_INSTRUCTIONS),"$$ADDITIONAL_INSTRUCTIONS",); \
	fi

crop-screenshots:
	bal run -- crop-screenshots

crop-screenshots-dry:
	bal run -- crop-screenshots dry-run

crop-screenshots-backup:
	bal run -- crop-screenshots backup

start-agent: python/.venv/.installed
	@echo "→ Starting Python agent server (python/agent_server.py)..."
	cd python && unset CLAUDECODE && .venv/bin/python agent_server.py --port $(AGENT_SERVER_PORT)

stop-agent:
	@echo "→ Sending shutdown to agent server..."
	curl -s -X POST http://localhost:$(AGENT_SERVER_PORT)/shutdown || echo "Agent server not running."

# ── Publish docs ─────────────────────────────────────────────────────────────
# Defaults are read from Config.toml by publish_docs.py.
# Set these Makefile vars to override Config.toml values for a single run.
# DOCS_REPO          — override the docs-integrator path
# DOCS_UPSTREAM      — GitHub org/repo for docs-integrator PRs
# DOCS_BASE_BRANCH   — base branch for docs-integrator PRs
# PUBLISH_ARGS       — extra flags passed to publish_docs.py

DOCS_REPO ?=
DOCS_UPSTREAM ?=
DOCS_BASE_BRANCH ?=
DOCS_BRANCH ?= docs/connector-docs
SAMPLES_BRANCH ?= samples/connector-samples

_pipeline_cmd = python/.venv/bin/python python/pipeline.py

_publish_docs_cmd = python/.venv/bin/python python/publish_docs.py \
  $(if $(DOCS_REPO),--docs-repo "$(DOCS_REPO)",) \
  $(if $(DOCS_UPSTREAM),--upstream "$(DOCS_UPSTREAM)",) \
  $(if $(DOCS_BASE_BRANCH),--base-branch "$(DOCS_BASE_BRANCH)",) \
  $(PUBLISH_ARGS)

publish-docs: python/.venv/.installed
	@echo "→ Publishing connector docs..."
	$(_publish_docs_cmd)

publish-docs-dry: python/.venv/.installed
	@echo "→ Publishing connector docs (dry run)..."
	$(_publish_docs_cmd) --dry-run

publish-docs-no-pr: python/.venv/.installed
	@echo "→ Publishing connector docs (branch + commit only, no PR)..."
	$(_publish_docs_cmd) --no-pr

# ── Batch docs (commit per connector → one PR) ────────────────────────────────
# Commit one connector's artifacts to a shared branch, then create one PR for all.
#
# Named overrides for pipeline.py commit-docs / pr-docs:
#   CATEGORY=<cat>          Override auto-detected connector category
#   ARTIFACTS_DIR=<path>    Override artifacts directory (default: ./artifacts)
#   DOCS_FORK=<owner/repo>  Override fork slug (default: inferred from git remote)
#   BATCH_COMMIT_DOCS_ARGS  Extra flags forwarded verbatim to pipeline.py commit-docs
#   BATCH_PR_DOCS_ARGS      Extra flags forwarded verbatim to pipeline.py pr-docs
#
# Workflow:
#   Run pipeline for connector A → make batch-commit-docs
#   Run pipeline for connector B → make batch-commit-docs
#   ...
#   make batch-pr-docs BRANCH=docs/connector-docs

CATEGORY ?=
ARTIFACTS_DIR ?=
DOCS_FORK ?=
BATCH_COMMIT_DOCS_ARGS ?=
BATCH_PR_DOCS_ARGS ?=

_batch_commit_cmd = $(_pipeline_cmd) commit-docs \
  $(if $(DOCS_REPO),--docs-repo "$(DOCS_REPO)",) \
  $(if $(DOCS_FORK),--fork "$(DOCS_FORK)",) \
  $(if $(DOCS_UPSTREAM),--upstream "$(DOCS_UPSTREAM)",) \
  $(if $(DOCS_BASE_BRANCH),--base-branch "$(DOCS_BASE_BRANCH)",) \
  $(if $(BRANCH),--branch "$(BRANCH)",) \
  $(if $(CATEGORY),--category "$(CATEGORY)",) \
  $(if $(ARTIFACTS_DIR),--artifacts-dir "$(ARTIFACTS_DIR)",) \
  $(BATCH_COMMIT_DOCS_ARGS)

_batch_pr_cmd = $(_pipeline_cmd) pr-docs \
  $(if $(DOCS_REPO),--docs-repo "$(DOCS_REPO)",) \
  $(if $(DOCS_FORK),--fork "$(DOCS_FORK)",) \
  $(if $(DOCS_UPSTREAM),--upstream "$(DOCS_UPSTREAM)",) \
  $(if $(DOCS_BASE_BRANCH),--base-branch "$(DOCS_BASE_BRANCH)",) \
  --branch "$(BRANCH)" \
  $(BATCH_PR_DOCS_ARGS)

batch-commit-docs: python/.venv/.installed
	@echo "→ Committing connector docs to batch branch$(if $(BRANCH), $(BRANCH),: docs/connector-docs)..."
	$(_batch_commit_cmd)

batch-commit-docs-dry: python/.venv/.installed
	@echo "→ Dry run: commit connector docs to batch branch$(if $(BRANCH), $(BRANCH),: docs/connector-docs)..."
	$(_batch_commit_cmd) --dry-run

batch-pr-docs: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required. Usage: make batch-pr-docs BRANCH=docs/batch-april-2026" && exit 1)
	@echo "→ Creating PR from batch branch: $(BRANCH)"
	$(_batch_pr_cmd)

batch-pr-docs-dry: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required." && exit 1)
	@echo "→ Dry run: create PR from batch branch: $(BRANCH)"
	$(_batch_pr_cmd) --dry-run

# ── Publish sample ────────────────────────────────────────────────────────────
# Defaults are read from Config.toml by publish_sample.py.
# Set these Makefile vars to override Config.toml values for a single run.
# CODE_SERVER_PORT         — override code-server port
# SAMPLES_REPO             — override integration-samples path
# INTEGRATION_UPSTREAM     — GitHub org/repo for integration samples PRs
# INTEGRATION_BASE_BRANCH  — base branch for integration samples PRs
# NO_PR                    — set to 1 to push branch without creating a PR
# PUBLISH_SAMPLE_ARGS      — extra flags passed to publish_sample.py

CODE_SERVER_PORT ?=
SAMPLES_REPO ?=
PROJECT_PATH ?=
INTEGRATION_UPSTREAM ?=
INTEGRATION_BASE_BRANCH ?=
NO_PR ?=
PUBLISH_SAMPLE_ARGS ?=

_publish_sample_cmd = python/.venv/bin/python python/publish_sample.py \
  $(if $(CODE_SERVER_PORT),--url "http://localhost:$(CODE_SERVER_PORT)",) \
  $(if $(SAMPLES_REPO),--samples-repo "$(SAMPLES_REPO)",) \
  $(if $(PROJECT_PATH),--project-path "$(PROJECT_PATH)",) \
  $(if $(INTEGRATION_UPSTREAM),--upstream "$(INTEGRATION_UPSTREAM)",) \
  $(if $(INTEGRATION_BASE_BRANCH),--base-branch "$(INTEGRATION_BASE_BRANCH)",) \
  $(if $(NO_PR),--no-pr,) \
  $(PUBLISH_SAMPLE_ARGS)

publish-sample: python/.venv/.installed
	@echo "→ Publishing integration sample, deleting local project, closing tabs..."
	$(_publish_sample_cmd)

publish-sample-dry: python/.venv/.installed
	@echo "→ Publishing integration sample (dry run)..."
	$(_publish_sample_cmd) --dry-run

publish-sample-no-pr: python/.venv/.installed
	@echo "→ Publishing integration sample (branch + commit only, no PR)..."
	$(_publish_sample_cmd) --no-pr

publish-sample-no-publish: python/.venv/.installed
	@echo "→ Deleting local project and closing editor tabs (skip sample publishing)..."
	$(_publish_sample_cmd) --no-publish

# ── Batch samples (commit per connector → one PR) ─────────────────────────────
# Commit one sample to a shared branch, then create one PR for all.
#
# Named overrides:
#   BATCH_COMMIT_SAMPLE_ARGS  Extra flags forwarded verbatim to pipeline.py commit-sample
#   BATCH_PR_SAMPLES_ARGS     Extra flags forwarded verbatim to pipeline.py pr-samples
#   (CODE_SERVER_PORT, SAMPLES_REPO, PROJECT_PATH, INTEGRATION_UPSTREAM,
#    INTEGRATION_BASE_BRANCH are shared with the publish-sample targets above)
#
# Workflow:
#   Run pipeline for connector A → make batch-commit-sample
#   Run pipeline for connector B → make batch-commit-sample
#   ...
#   make batch-pr-samples BRANCH=samples/connector-samples

BATCH_COMMIT_SAMPLE_ARGS ?=
BATCH_PR_SAMPLES_ARGS ?=

_batch_commit_sample_cmd = $(_pipeline_cmd) commit-sample \
  $(if $(CODE_SERVER_PORT),--url "http://localhost:$(CODE_SERVER_PORT)",) \
  $(if $(SAMPLES_REPO),--samples-repo "$(SAMPLES_REPO)",) \
  $(if $(PROJECT_PATH),--project-path "$(PROJECT_PATH)",) \
  $(if $(INTEGRATION_UPSTREAM),--upstream "$(INTEGRATION_UPSTREAM)",) \
  $(if $(INTEGRATION_BASE_BRANCH),--base-branch "$(INTEGRATION_BASE_BRANCH)",) \
  $(if $(BRANCH),--branch "$(BRANCH)",) \
  $(BATCH_COMMIT_SAMPLE_ARGS)

_batch_pr_samples_cmd = $(_pipeline_cmd) pr-samples \
  $(if $(SAMPLES_REPO),--samples-repo "$(SAMPLES_REPO)",) \
  $(if $(INTEGRATION_UPSTREAM),--upstream "$(INTEGRATION_UPSTREAM)",) \
  $(if $(INTEGRATION_BASE_BRANCH),--base-branch "$(INTEGRATION_BASE_BRANCH)",) \
  --branch "$(BRANCH)" \
  $(BATCH_PR_SAMPLES_ARGS)

batch-commit-sample: python/.venv/.installed
	@echo "→ Committing connector sample to batch branch$(if $(BRANCH), $(BRANCH),: samples/connector-samples)..."
	$(_batch_commit_sample_cmd)

batch-commit-sample-dry: python/.venv/.installed
	@echo "→ Dry run: commit connector sample to batch branch$(if $(BRANCH), $(BRANCH),: samples/connector-samples)..."
	$(_batch_commit_sample_cmd) --dry-run

batch-pr-samples: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required. Usage: make batch-pr-samples BRANCH=samples/batch-april-2026" && exit 1)
	@echo "→ Creating PR from batch samples branch: $(BRANCH)"
	$(_batch_pr_samples_cmd)

batch-pr-samples-dry: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required." && exit 1)
	@echo "→ Dry run: create PR from batch samples branch: $(BRANCH)"
	$(_batch_pr_samples_cmd) --dry-run

# ── Batch Run (queue multiple connectors) ─────────────────────────────────────
BATCH_CONFIG ?= batch_connectors.json
BATCH_RUN_ARGS ?=

batch-run: python/.venv/.installed
	@echo "→ Running batch pipeline from $(BATCH_CONFIG)..."
	$(_pipeline_cmd) batch-run --config "$(BATCH_CONFIG)" $(BATCH_RUN_ARGS)

batch-run-dry: python/.venv/.installed
	@echo "→ Batch pipeline dry run..."
	$(_pipeline_cmd) batch-run --config "$(BATCH_CONFIG)" --dry-run $(BATCH_RUN_ARGS)

_pipeline_commit_cmd = $(_pipeline_cmd) commit \
  $(if $(DOCS_REPO),--docs-repo "$(DOCS_REPO)",) \
  $(if $(DOCS_UPSTREAM),--docs-upstream "$(DOCS_UPSTREAM)",) \
  $(if $(DOCS_BASE_BRANCH),--docs-base-branch "$(DOCS_BASE_BRANCH)",) \
  --docs-branch "$(DOCS_BRANCH)" \
  $(if $(CATEGORY),--category "$(CATEGORY)",) \
  $(if $(ARTIFACTS_DIR),--artifacts-dir "$(ARTIFACTS_DIR)",) \
  $(if $(CODE_SERVER_PORT),--url "http://localhost:$(CODE_SERVER_PORT)",) \
  $(if $(SAMPLES_REPO),--samples-repo "$(SAMPLES_REPO)",) \
  $(if $(PROJECT_PATH),--project-path "$(PROJECT_PATH)",) \
  $(if $(INTEGRATION_UPSTREAM),--samples-upstream "$(INTEGRATION_UPSTREAM)",) \
  $(if $(INTEGRATION_BASE_BRANCH),--samples-base-branch "$(INTEGRATION_BASE_BRANCH)",) \
  --samples-branch "$(SAMPLES_BRANCH)"

_pipeline_pr_cmd = $(_pipeline_cmd) pr \
  $(if $(DOCS_REPO),--docs-repo "$(DOCS_REPO)",) \
  $(if $(DOCS_UPSTREAM),--docs-upstream "$(DOCS_UPSTREAM)",) \
  $(if $(DOCS_BASE_BRANCH),--docs-base-branch "$(DOCS_BASE_BRANCH)",) \
  --docs-branch "$(DOCS_BRANCH)" \
  $(if $(SAMPLES_REPO),--samples-repo "$(SAMPLES_REPO)",) \
  $(if $(INTEGRATION_UPSTREAM),--samples-upstream "$(INTEGRATION_UPSTREAM)",) \
  $(if $(INTEGRATION_BASE_BRANCH),--samples-base-branch "$(INTEGRATION_BASE_BRANCH)",) \
  --samples-branch "$(SAMPLES_BRANCH)"

pipeline-commit: python/.venv/.installed
	@echo "→ Committing docs + sample to batch branches..."
	$(_pipeline_commit_cmd)

pipeline-commit-dry: python/.venv/.installed
	@echo "→ Dry run: commit docs + sample to batch branches..."
	$(_pipeline_commit_cmd) --dry-run

pipeline-pr: python/.venv/.installed
	@echo "→ Creating docs + sample PRs from batch branches..."
	$(_pipeline_pr_cmd)

pipeline-pr-dry: python/.venv/.installed
	@echo "→ Dry run: create docs + sample PRs from batch branches..."
	$(_pipeline_pr_cmd) --dry-run

# Aliases for backward compatibility
cleanup: publish-sample
cleanup-dry: publish-sample-dry

# ── Artifacts ────────────────────────────────────────────────────────────────
clean:
	@echo "→ Cleaning artifacts/, target/, Dependencies.toml, python/.venv..."
	rm -rf artifacts/ target/ Dependencies.toml python/.venv
	@echo "Done."

clean-artifacts:
	@echo "→ Removing artifacts/ directory..."
	rm -rf artifacts/
