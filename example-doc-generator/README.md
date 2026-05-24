# Example Doc Generator

This project generates WSO2 Integrator example documentation with screenshots.
It can run one connector, run one trigger, or process a mixed batch queue.

The pipeline is:

```text
CLI input -> Ballerina orchestration -> Claude Agent + Playwright MCP -> Markdown guide + screenshots
```

The Ballerina app orchestrates the pipeline. Agent execution runs in-process
through a small Java interop bridge over the Claude Agent SDK for Java and
Playwright MCP. Screenshot processing and publishing are also implemented in
Ballerina.

## Prerequisites

Install these first:

| Tool | Required |
|------|----------|
| Ballerina | `2201.13.x` |
| Java | `21` |
| Gradle | latest |
| Node.js | LTS+ |
| Claude Code CLI | latest |
| Anthropic API key | for Ballerina API calls and Claude agent execution |

`code-server` is installed by the pipeline if it is missing.

## Setup

Run all commands from `example-doc-generator/`.

1. Create the Ballerina config:

```bash
cp Config.toml.example Config.toml
```

Set `anthropicApiKey` in `Config.toml`. If you plan to publish connector output with
`with-pr`, also set the docs-integrator and integration-samples fork values.

2. Export the Anthropic key for Claude agent execution:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

3. Build the Ballerina app:

```bash
gradle -p native-bridge copyNativeBridgeJar
bal build
```

## Optional Claude Code Local Settings

`.claude/` is ignored because it contains local Claude Code preferences and
permissions. Keep shared MCP setup in the tracked `.mcp.json`; recreate
`.claude/settings.json` locally only if your Claude Code setup needs it.

## Run One Connector

Connector mode is the default.

```bash
bal run -- mysql
```

With extra guidance:

```bash
bal run -- zoom.meetings "Use BearerTokenConfig for authentication."
```

To publish the generated connector guide, screenshots, and integration sample,
commit and push them, and create PRs, add `with-pr`:

```bash
bal run -- snowflake with-pr
```

Without `with-pr`, the pipeline only writes local artifacts and does not modify
`docs-integrator` or `integration-samples`.

To replay a saved connector prompt:

```bash
bal run -- prompt artifacts/execution-prompt/<prompt-file>.md
```

## Run One Trigger

Use `trigger` as the first argument. The pipeline derives the Ballerina Central
package path as `ballerinax/<trigger-name>`.

```bash
bal run -- trigger trigger.github
```

With extra guidance:

```bash
bal run -- trigger trigger.github "Use IssuesService and the onOpened handler."
```

Do not pass `--trigger` or `TRIGGER_PACKAGE`.

To replay a saved trigger prompt, use the same prompt mode. Trigger prompts are
detected from the prompt filename:

```bash
bal run -- prompt artifacts/execution-prompt/<trigger-prompt-file>.md
```

## Batch Runs

Batch runs process items sequentially and archive each run under
`artifacts_archive/`.

1. Create a batch config:

```bash
cp batch_items.json.example batch_items.json
```

2. Add connector and trigger entries:

```json
{
  "items": [
    { "type": "connector", "name": "mysql" },
    {
      "type": "connector",
      "name": "zoom.meetings",
      "instructions": "Use BearerTokenConfig for authentication."
    },
    {
      "type": "trigger",
      "name": "trigger.github",
      "instructions": "Use IssuesService and the onOpened handler."
    }
  ]
}
```

Rules:

- `type` is required and must be `connector` or `trigger`.
- `name` is required.
- `instructions` is optional.
- Batch mode does not resume.
- Batch mode creates docs and sample PRs only when `with-pr` is passed.
- Batch mode fails fast if `artifacts/` already exists to avoid archiving stale output.
- Pressing `Ctrl+C` stops the active child pipeline before the batch exits.

3. Make sure no current run artifacts are present:

```bash
rm -rf artifacts
```

4. Run the queue:

```bash
bal run -- batch config=batch_items.json
```

With a longer per-item timeout:

```bash
bal run -- batch config=batch_items.json timeout=7200
```

To publish connector docs and samples from each successful batch item into
batch branches and create PRs at the end:

```bash
bal run -- batch config=batch_items.json with-pr
```

## PRs From Existing Artifacts

To create docs and sample PRs from an existing single-run `artifacts/`
directory without running the generator again:

```bash
bal run -- only-pr
```

To publish successful connector archives from `artifacts_archive/` into the
shared batch branches and create the batch PRs:

```bash
bal run -- only-batch-pr
```

`only-batch-pr` skips failed archives, no-artifact placeholders, trigger
archives, and folders that do not contain connector run-log metadata.

## What a Run Produces

Single runs write to `artifacts/`:

| Path | Contents |
|------|----------|
| `artifacts/execution-prompt/` | Generated execution prompt sent to the agent |
| `artifacts/workflow-docs/` | Final Markdown guide |
| `artifacts/screenshots/` | Captured and cropped screenshots |
| `artifacts/run-log/` | Target name, project path, timing, costs, and output paths |

Batch runs move each item's `artifacts/` directory to `artifacts_archive/<slug>`
or `artifacts_archive/<slug>_FAILED`. If a run produces no artifacts, the batch
runner creates a `<slug>_NO_ARTIFACTS/README.txt` placeholder.

At the end of a single pipeline run, the in-process Claude agent SDK session is
closed automatically.

## Publishing Connector Output

Publishing is integrated into the Ballerina pipeline and is opt-in. Passing
`with-pr` copies the generated connector `example.md` and screenshots into the
local `docs-integrator` fork, updates `en/sidebars.ts`, copies the generated
Ballerina project into the local `integration-samples` fork, commits both repos,
pushes both branches, and creates PRs with `gh`.

The publisher uses these `Config.toml` values:

- `docsIntegratorRepo`, default `../../docs-integrator`
- `docsIntegratorFork`, or the fork inferred from the docs repo `origin`
- `docsIntegratorUpstream`, default `wso2/docs-integrator`
- `docsIntegratorBaseBranch`, default `main`
- `integrationSamplesRepo`, default `../../integration-samples`
- `integrationSamplesFork`, or the fork inferred from the samples repo `origin`
- `integrationSamplesUpstream`, default `wso2/integration-samples`
- `integrationSamplesBaseBranch`, default `main`

Trigger publishing is not automated yet.

## Java Native Bridge

The pipeline calls the Claude agent through Ballerina Java interop. Build the
bridge before `bal build`:

```bash
gradle -p native-bridge copyNativeBridgeJar
```

The bridge also provides image processing through Java ImageIO. It expects
`org.springaicommunity:claude-code-sdk:1.0.0-SNAPSHOT` in the local Maven cache.
If it is missing, build/install `spring-ai-community/claude-agent-sdk-java`
first.

If VS Code still reports that `ClaudeAgentBridge.java` is not on the classpath,
run `Java: Clean Java Language Server Workspace` from the command palette and
reload the window. The Java Gradle project lives under `native-bridge`.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| API key validation failed | Set `anthropicApiKey` in `Config.toml` and export `ANTHROPIC_API_KEY` |
| `claude` not found | Install Claude Code CLI and verify with `claude --version` |
| `npx` not found | Install Node.js/npm and verify with `npx --version` |
| Batch fails because `artifacts/` exists | Move or delete `artifacts/` after reviewing it |
| Java native bridge build fails | Ensure Gradle can resolve dependencies from Maven local/Central, then rerun `gradle -p native-bridge copyNativeBridgeJar` |
| PR creation fails | Verify `gh auth status` and both publishing fork remotes |
| Ballerina build error | Run `bal clean && bal build` |
| Playwright MCP error | Verify with `npx --yes @playwright/mcp@latest --help` |
| Need to clear generated output | Run `rm -rf artifacts` after reviewing the output |

The pipeline removes `.yaml` and `.yml` files from screenshot directories after
cropping, before publishing or archiving artifacts.
