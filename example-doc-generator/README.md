# Example Doc Generator

An AI-driven pipeline that automates WSO2 Integrator low-code **connector** documentation by default, with an explicit trigger-generation mode. It uses **Ballerina** to orchestrate prompt generation via the Claude API, then runs a **Python agent server** (Claude Agent SDK + Playwright MCP) that operates a **code-server** instance to capture screenshots and produce step-by-step integration guides.

```
Connector/Trigger → Claude generates execution prompt → Agent executes via Playwright MCP → Artifacts (docs + screenshots)
```

Default connector generation supports Ballerina Central connectors such as `mysql`, `kafka`, `aws.sns`, and similar `ballerinax/<connector>` packages.

Trigger mode supports all 15 WSO2 Integrator trigger types across three categories:
- **Integration as API**: HTTP Service (`ballerina/http`), GraphQL Service (`ballerina/graphql`), TCP Service (`ballerina/tcp`)
- **Event Integration**: Kafka, RabbitMQ, MQTT, Azure Service Bus, Salesforce, Twilio, GitHub, Solace, CDC for MSSQL, CDC for PostgreSQL
- **File Integration**: FTP/SFTP (`ballerina/ftp`), Local Files (`ballerina/file`)

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Ballerina | 2201.13.1 | [ballerina.io/downloads](https://ballerina.io/downloads/) |
| Python | 3.11+ | [python.org](https://www.python.org/downloads/) |
| uv | latest | [docs.astral.sh/uv](https://docs.astral.sh/uv/getting-started/installation/) |
| Node.js | LTS+ | [nodejs.org](https://nodejs.org/) |
| Claude Code CLI | latest | [claude.ai/code](https://claude.ai/code) |
| code-server | latest | auto-installed by pipeline |
| WSO2 Integrator extension | latest | installed from marketplace by pipeline |

## Setup

**1. Create Config.toml**

```bash
cp Config.toml.example Config.toml
# Fill in llmApiKey, docsIntegratorFork, and any local repo paths
```

**2. Install dependencies**

```bash
make setup
```

**3. Run the pipeline**

```bash
# Connector generation is the default:
make run CONNECTOR=mysql
make run CONNECTOR=mysql ADDITIONAL_INSTRUCTIONS='Use a local MySQL database'
# or directly:
bal run -- mysql

# Trigger generation is explicit:
make run TRIGGER=trigger.github PACKAGE=ballerinax/trigger.github
# For ballerina/* org triggers:
make run TRIGGER=http PACKAGE=ballerina/http
# Package defaults to ballerinax/<name> if omitted:
make run TRIGGER=kafka
# or directly:
bal run -- -t trigger.github ballerinax/trigger.github
```

Artifacts are saved under `artifacts/` (git-ignored).

## Configuration

Configuration is kept in `Config.toml`. Copy `Config.toml.example` to get
started. The Ballerina pipeline and Python scripts both read this file.

Real environment variables can still override values for CI or one-off shell
runs, but no `.env` file is required.

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `llmApiKey` | ✅ | — | Anthropic API key for Ballerina AI calls |
| `codeServerPort` | No | `8080` | Port for the code-server instance |
| `agentServerPort` | No | `8765` | Port for the Python agent server |
| `integrationSamplesRepo` | No | `../integration-samples` | Local path to integration-samples fork |
| `docsIntegratorRepo` | No | `../docs-integrator` | Local path to docs-integrator fork |
| `integrationSamplesUpstream` | No | `wso2/integration-samples` | GitHub org/repo for samples PRs |
| `integrationSamplesBaseBranch` | No | `main` | Base branch for samples PRs |
| `docsIntegratorFork` | ✅ for docs PRs | — | Your fork of docs-integrator (org/repo) |
| `docsIntegratorUpstream` | No | `wso2/docs-integrator` | GitHub org/repo for docs PRs |
| `docsIntegratorBaseBranch` | No | `main` | Base branch for docs PRs |

> **Connector generation is the default:** pass the connector name with `make run CONNECTOR=mysql` or `bal run -- mysql`.

> **Trigger generation uses `-t`:** pass trigger name/package with `make run TRIGGER=trigger.github PACKAGE=ballerinax/trigger.github` or `bal run -- -t trigger.github ballerinax/trigger.github`. Package defaults to `ballerinax/<name>` when omitted.

> **Never commit `Config.toml`** — it is git-ignored.

## Project Structure

```
example-doc-generator/
├── main.bal                        # Pipeline entry point with connector/trigger mode selection
├── config.bal                      # All configurable fields
├── Ballerina.toml                  # Package manifest
├── Config.toml.example             # Configuration template
├── Makefile                        # Common commands
│
├── modules/
│   ├── ai_client/ai_client.bal     # Anthropic API calls (generate, slug, enforce)
│   ├── agent_client/agent_client.bal  # REST client for the Python agent server
│   ├── prompts/
│   │   ├── system_prompt.bal       # Connector XML-tagged execution prompt template
│   │   ├── user_prompt.bal         # Connector user message builder
│   │   ├── system_prompt_trigger.bal  # Trigger XML-tagged execution prompt template
│   │   ├── user_prompt_trigger.bal    # Trigger user message builder
│   │   └── doc_enforcement_prompt.bal  # Doc structure enforcement prompt
│   └── utils/                      # Logger, file I/O, code-server & agent server utils
│
├── python/
│   ├── agent_server.py             # aiohttp server wrapping Claude Agent SDK
│   ├── pipeline.py                 # Unified batch-run, commit, and PR command surface
│   ├── publish_sample.py           # Publishes integration sample PR + cleans workspace
│   ├── publish_docs.py             # Publishes docs to docs-integrator fork + creates PR
│   └── requirements.txt
│
├── .mcp.json                       # Playwright MCP config for Claude Code subagent
├── .claude/settings.json           # Permissions + model for Claude Code subagent
│
└── artifacts/                      # All generated output (git-ignored)
    ├── execution-prompt/           # Generated execution prompts
    ├── workflow-docs/              # Step-by-step connector guides (Markdown)
    ├── screenshots/                # Captured browser screenshots (cropped)
    └── run-log/                    # JSON run logs (cost, tokens, timing)
```

## Makefile Reference

```
Setup
  make setup                Install all deps (Python venv + Playwright + Ballerina build)
  make setup-python         Create python/.venv and install Python deps
  make setup-bal            Build the Ballerina project

Run
  make run CONNECTOR=mysql                               Run the full pipeline for a connector
  make run CONNECTOR=mysql ADDITIONAL_INSTRUCTIONS='...' Run with per-connector guidance
  make run TRIGGER=trigger.github                        Run the full pipeline for a trigger (-t)
  make run TRIGGER=http PACKAGE=ballerina/http           Run trigger mode with explicit package path
  make start-agent          Start the Python agent server in the foreground
  make stop-agent           Send shutdown to the agent server

Publish
  make publish-docs         Publish docs + create PR to docs-integrator
  make publish-docs-dry     Dry run — print planned actions, no changes

Batch / Review
  make batch-run            Run connector/trigger queue from batch_connectors.json
  make batch-run-dry        Print planned queue execution, no changes
  make pipeline-commit      Commit reviewed docs + sample to shared batch branches
  make pipeline-pr          Create docs + sample PRs from shared batch branches

Direct Python
  python python/pipeline.py batch-run --config batch_connectors.json
  python python/pipeline.py commit --docs-branch docs/batch --samples-branch samples/batch
  python python/pipeline.py pr --docs-branch docs/batch --samples-branch samples/batch

Screenshots
  make crop-screenshots     Crop UI chrome from all screenshots via Ballerina imagekit
  make crop-screenshots-dry Preview what would be cropped (no changes)

Artifacts
  make clean                Remove artifacts/, target/, Dependencies.toml, python/.venv
  make clean-artifacts      Remove only the artifacts/ directory
```

Run `make help` for the full list with configurable variables.

## Pipeline Phases

| Phase | Steps | Description |
|-------|-------|-------------|
| Pre-flight | 1–2 | Validate API key; check Claude Code CLI is installed |
| Infrastructure | 3–6 | Install/start code-server; install WSO2 Integrator from marketplace; install/start Python agent server |
| Prompt generation | 7–10 | Build prompts → call Claude → format → save execution prompt |
| Agent execution | 11 | POST prompt to agent server; stream logs until done |
| Post-processing | 12–14 | Enforce doc structure; crop screenshots; write run log |

## Python Agent Server

`python/agent_server.py` wraps the Claude Agent SDK as a lightweight HTTP server.

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/run` | Submit job: `{ "prompt_path": "..." }` → `{ "job_id": "..." }` |
| `GET` | `/jobs/<id>` | Poll: `{ "status": "queued\|running\|done\|error", "logs": [...], "cost": {...} }` |
| `GET` | `/health` | `{ "status": "ok" }` |
| `POST` | `/shutdown` | Graceful stop |

```bash
make start-agent                                    # start in foreground
make stop-agent                                     # send shutdown
cd python && .venv/bin/python agent_server.py --port 9000  # custom port
```

## GitHub Actions

Two workflows are included under `.github/workflows/`:

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `connector-docs-automation.yml` | `workflow_dispatch` | Runs the full pipeline and uploads artifacts |
| `publish-connector-docs.yml` | `workflow_run` / `workflow_dispatch` | Places generated docs into docs-integrator and creates a PR |

### Required Secrets

Add these under **Settings → Environments → `docs-automation` → Secrets**:

| Secret | Description |
|--------|-------------|
| `LLM_API_KEY` | Anthropic API key — used for all Claude calls |
| `DOCS_INTEGRATOR_TOKEN` | GitHub PAT with `repo` scope — used to push branches to your docs-integrator fork and open PRs against the upstream |

### Required Environment

Create a GitHub environment named **`docs-automation`** at **Settings → Environments → New environment**.

### Workflow Inputs (`connector-docs-automation.yml`)

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `userGoal` | ✅ | — | Integration to document |
| `docsIntegratorFork` | ✅ | — | Your fork of docs-integrator (e.g. `your-org/docs-integrator`) |
| `codeServerPort` | No | `8080` | code-server port |
| `agentServerPort` | No | `8765` | Agent server port |
| `docsIntegratorUpstream` | No | `wso2/docs-integrator` | Upstream repo for docs PRs |
| `docsIntegratorBaseBranch` | No | `dev` | Base branch for docs PRs |
| `integrationSamplesUpstream` | No | `wso2/integration-samples` | Upstream repo for samples PRs |
| `integrationSamplesBaseBranch` | No | `main` | Base branch for samples PRs |

## Troubleshooting

| Error | Fix |
|-------|-----|
| API key validation failed | Set `llmApiKey` in `Config.toml` |
| Claude Code CLI not found | Install from [claude.ai/code](https://claude.ai/code), verify with `claude --version` |
| Agent server not ready | Run `make start-agent` to see Python errors; check `curl http://localhost:8765/health` |
| `uv: command not found` | `curl -LsSf https://astral.sh/uv/install.sh \| sh && source ~/.zshrc` |
| `claude_agent_sdk` import error | `make setup-python` |
| code-server install failed | `curl -fsSL https://code-server.dev/install.sh \| sh` |
| Ballerina build errors | `bal clean && make setup-bal` |
| Playwright MCP missing | `npm install -g @playwright/mcp@latest` |
