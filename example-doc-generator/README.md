# Example Doc Generator

This project generates WSO2 Integrator example documentation with screenshots.
It can run one connector or trigger at a time, or process a batch queue
sequentially.

The pipeline is:

```text
CLI input -> Claude prompt generation -> Claude Agent + Playwright MCP -> Markdown guide + screenshots
```

The Ballerina app orchestrates the run. The Python agent server runs the Claude
Agent SDK and Playwright MCP against code-server.

## Prerequisites

Install these first:

| Tool | Required |
|------|----------|
| Ballerina | `2201.13.x` |
| Python | `3.11+` |
| uv | latest |
| Node.js | LTS+ |
| Claude Code CLI | latest |
| Anthropic API key | for both Ballerina API calls and the agent server |

`code-server` is installed by the pipeline if it is missing.

## Setup

Run all commands from `example-doc-generator/`.

1. Create the Ballerina config:

```bash
cp Config.toml.example Config.toml
```

Set `llmApiKey` in `Config.toml`.

2. Create the Python scripts config:

```bash
cp .env.example .env
```

At minimum, set `DOCS_INTEGRATOR_FORK` if you plan to publish docs.

3. Export the Anthropic key for the Python agent server:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

4. Install dependencies and build:

```bash
make setup
```

## Run One Connector

Use `make run` for connector examples. Connector mode is the default.

```bash
make run CONNECTOR=mysql
```

With extra guidance:

```bash
make run CONNECTOR=zoom.meetings ADDITIONAL_INSTRUCTIONS='Use BearerTokenConfig for authentication.'
```

Direct Ballerina command:

```bash
bal run -- mysql
bal run -- zoom.meetings "Use BearerTokenConfig for authentication."
```

## Run One Trigger

Use `make run-trigger` for trigger examples. A trigger run needs both the
trigger name and the full Ballerina Central package path.

```bash
make run-trigger TRIGGER=trigger.github TRIGGER_PACKAGE=ballerinax/trigger.github
```

With extra guidance:

```bash
make run-trigger \
  TRIGGER=trigger.github \
  TRIGGER_PACKAGE=ballerinax/trigger.github \
  ADDITIONAL_INSTRUCTIONS='Use IssuesService and the onOpened handler.'
```

Direct Ballerina command:

```bash
bal run -- trigger trigger.github ballerinax/trigger.github
bal run -- trigger trigger.github ballerinax/trigger.github "Use IssuesService and the onOpened handler."
```

## What a Run Produces

Generated output is written under `artifacts/`:

| Path | Contents |
|------|----------|
| `artifacts/execution-prompt/` | The generated execution prompt sent to the agent |
| `artifacts/workflow-docs/` | The final Markdown guide |
| `artifacts/screenshots/` | Captured and cropped screenshots |
| `artifacts/run-log/` | Cost, timing, prompt path, and generated-doc path |

At the end of a run, the pipeline stops the Python agent server automatically.

## Batch Runs

Batch runs process items sequentially and archive each run under
`artifacts_archive/`.

1. Create a batch config:

```bash
cp batch_connectors.json.example batch_connectors.json
```

2. Add connector entries:

```json
{
  "connectors": [
    { "name": "mysql" },
    {
      "name": "zoom.meetings",
      "instructions": "Use BearerTokenConfig for authentication."
    }
  ],
  "docsBranch": "docs/connector-docs",
  "samplesBranch": "samples/connector-samples"
}
```

3. Add trigger entries with `type` and `package`:

```json
{
  "type": "trigger",
  "name": "trigger.github",
  "package": "ballerinax/trigger.github",
  "instructions": "Use IssuesService and the onOpened handler."
}
```

4. Preview the queue:

```bash
make batch-run-dry
```

5. Run the queue:

```bash
make batch-run
```

Useful options:

```bash
make batch-run BATCH_CONFIG=my_batch.json
make batch-run BATCH_RUN_ARGS='--no-resume'
make batch-run BATCH_RUN_ARGS='--timeout 5400'
```

The batch runner stores progress in `batch_state.json`. Use `--no-resume` to
start fresh.

## Publishing Connector Output

The current publish helpers are connector-focused.

Publish the latest generated connector doc:

```bash
make publish-docs
```

Publish the latest generated connector sample:

```bash
make publish-sample
```

Publish both:

```bash
make publish-all
```

Dry-run variants:

```bash
make publish-docs-dry
make publish-sample-dry
make publish-all-dry
```

For batch connector publishing, run the pipeline for each item, review the
archive, then commit approved artifacts to shared branches:

```bash
make batch-commit-docs ARTIFACTS_DIR=artifacts_archive/mysql BRANCH=docs/connector-docs
make batch-commit-sample PROJECT_PATH=/path/to/generated/sample BRANCH=samples/connector-samples
make batch-pr-docs BRANCH=docs/connector-docs
make batch-pr-samples BRANCH=samples/connector-samples
```

Trigger publish helpers are not automated yet; review trigger artifacts in
`artifacts_archive/` and publish them manually.

## Agent Server

The pipeline starts and stops the agent server automatically. For debugging:

```bash
make start-agent
make stop-agent
curl http://localhost:8765/health
```

The server API is:

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/run` | Submit `{ "prompt_path": "..." }` |
| `GET` | `/jobs/<id>` | Poll logs, status, and cost |
| `GET` | `/health` | Health check |
| `POST` | `/shutdown` | Stop the server |

## Common Make Targets

```text
Setup
  make setup
  make setup-python
  make setup-bal

Run
  make run CONNECTOR=mysql
  make run-trigger TRIGGER=trigger.github TRIGGER_PACKAGE=ballerinax/trigger.github
  make batch-run
  make batch-run-dry

Screenshots
  make crop-screenshots
  make crop-screenshots-dry

Publish connectors
  make publish-docs
  make publish-sample
  make publish-all

Cleanup
  make clean-artifacts
  make clean
```

Run `make help` for every target and override variable.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| API key validation failed | Set `llmApiKey` in `Config.toml` and export `ANTHROPIC_API_KEY` |
| `claude` not found | Install Claude Code CLI and verify with `claude --version` |
| Agent server not ready | Run `make start-agent` and inspect the Python error |
| `uv` not found | Install uv from `https://docs.astral.sh/uv/` |
| Python dependency error | Run `make setup-python` |
| Ballerina build error | Run `bal clean && make setup-bal` |
| Playwright MCP error | Run `make setup-python`; the setup installs Chromium |
| Need to clear generated output | Run `make clean-artifacts` |
