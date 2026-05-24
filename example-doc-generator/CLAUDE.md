# CLAUDE.md

Project guidance for agents working in `example-doc-generator/`.

## Current Architecture

This project is Ballerina-first. Do not reintroduce the removed Python or
Makefile paths.

```text
CLI input
  -> Ballerina orchestrates the run
  -> Claude prompt generation through Anthropic API
  -> Java native bridge runs Claude Agent SDK for Java
  -> Agent uses Playwright MCP against code-server
  -> Ballerina post-processes docs, screenshots, logs, and publishing
```

Core pieces:

| Area | Location |
|------|----------|
| CLI and single-run pipeline | `main.bal` |
| Batch queue runner | `modules/batch_runner/` |
| Claude API calls | `modules/ai_client/` |
| Claude Agent SDK wrapper | `modules/agent_client/` and `modules/claude_agent_sdk/` |
| Prompt builders | `modules/prompts/` |
| Screenshot/image processing | `modules/image_processor/` and `modules/utils/screenshot_cropper_utils.bal` |
| Docs and sample publishing | `modules/docs_publisher/` |
| Java interop bridge | `native-bridge/` |

Every Ballerina module should keep module-specific type definitions in its own
`types.bal`.

## Setup And Build

Use `Config.toml` for Ballerina configuration. Do not use `.env` or
`.env.example`; they were intentionally removed.

```bash
cp Config.toml.example Config.toml
gradle -p native-bridge copyNativeBridgeJar
bal build
```

Required runtime values:

- `anthropicApiKey` in `Config.toml`
- `ANTHROPIC_API_KEY` exported for Claude Code / agent execution
- `docsIntegrator*` and `integrationSamples*` config values only when using
  `with-pr`

## Common Commands

```bash
bal run -- mysql
bal run -- zoom.meetings "Use BearerTokenConfig for authentication."
bal run -- snowflake with-pr
bal run -- only-pr
bal run -- trigger trigger.github
bal run -- trigger trigger.github "Use IssuesService and the onOpened handler."
bal run -- prompt artifacts/execution-prompt/<prompt-file>.md
bal run -- batch config=batch_items.json
bal run -- batch config=batch_items.json timeout=7200
bal run -- batch config=batch_items.json with-pr
bal run -- only-batch-pr
bal run -- crop-screenshots
```

There is no dry-run mode for cropping or publishing. Keep execution paths direct
unless the user explicitly asks for a planning-only mode.

## Publishing

Publishing is explicit through `with-pr`, `only-pr`, or `only-batch-pr`.

For connector runs, `with-pr` must:

- copy docs and screenshots into the configured `docs-integrator` fork
- update `en/sidebars.ts`
- copy the generated Ballerina project into the configured
  `integration-samples` fork
- commit and push both repos
- create one docs PR and one samples PR

For batch runs, `with-pr` publishes successful connector items into shared batch
branches and creates the docs and samples PRs after all items finish.
`only-batch-pr` publishes successful connector archives from `artifacts_archive/`
into those same batch branches without rerunning generation.

Trigger publishing is not implemented. Keep trigger runs artifact-only unless
that support is added deliberately.

## Important Constraints

- Do not add Python scripts, Python dependencies, `uv`, or Makefile targets.
- Do not add root Gradle wrappers/settings just to build the Java bridge; use
  `gradle -p native-bridge ...`.
- Do not add `.env` configuration. Use Ballerina configurables and
  `Config.toml.example`.
- Do not pass `--trigger` to `bal run`; use `bal run -- trigger <triggerName>`.
- Do not pass `TRIGGER_PACKAGE`; trigger package names are derived internally as
  `ballerinax/<trigger-name>`.
- Keep `.mcp.json` tracked. Keep `.claude/` local and ignored.
- Avoid broad helper modules when functionality belongs in an existing module.
- For Java modernizations, prefer specific catches and switch/pattern matching
  where it improves clarity.

## Verification

For code changes, run the narrowest useful checks:

```bash
gradle -p native-bridge copyNativeBridgeJar
bal build
```

For publishing changes, also inspect `modules/docs_publisher/` and verify the
single-run and batch `with-pr` paths still pass the correct repo config.

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
