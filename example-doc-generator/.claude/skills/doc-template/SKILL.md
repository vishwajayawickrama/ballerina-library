---
name: doc-template
description: Template and rules for writing workflow documentation after a WSO2 Integrator connector automation run. Covers document structure, step formatting, Mermaid diagram rules, screenshot embedding, and save location. Use when creating the final workflow documentation markdown file.
user-invocable: false
---

# Workflow Documentation Skill

After the automation is complete, write the workflow documentation.
Load the full template from [TEMPLATE.md](TEMPLATE.md) and follow it exactly.

## Pre-Writing Checklist

1. Review the screenshots taken during this run (in `artifacts/screenshots/` for this run's prefix). Verify that all 6 mandatory screenshots are present.
2. Match screenshots to steps by their sequential number (NN), not by expecting a fixed suffix.
3. Screenshots MUST be embedded in ascending filename-number order — never a higher number before a lower one.
4. Confirm relative path from `artifacts/workflow-docs/` to screenshots is `../screenshots/`.
5. Image paths MUST be relative — always `../screenshots/filename.png`. NEVER absolute paths.

## Numbered Sub-List Rule (MANDATORY)

If a step body paragraph contains **2 or more distinct sequential instructions**, format them as a numbered sub-list instead of a prose paragraph.

A "distinct sequential instruction" = any sentence describing a UI action (click, type, select, expand, fill, save, etc.) or a distinct configuration step.

Parameter bullet lines (`**Display Label** — description`) and screenshot references remain outside the numbered sub-list, after the last numbered item.

**CORRECT** — numbered sub-list (2+ instructions):

```markdown
### Step N: Add an automation trigger and configure the Send operation
1. On the canvas, click **+ Add Automation** to add a new automation entry point.
2. In the trigger configuration panel, set the interval to **1 minute** and click **Save**.
3. Inside the automation body, click **+**, expand the connection node, and select **Send**.
- **topic** — the Kafka topic to publish the message to
- **value** — the message payload as a byte array
![...](../screenshots/prefix_screenshot_05_operation_filled.png)
```

**CORRECT** — single sentence (only 1 instruction):

```markdown
### Step N: Search for the Redis connector in the palette
Type "redis" in the search box and click the **Redis** connector card.
![...](../screenshots/prefix_screenshot_01_palette.png)
```

**WRONG** — multiple instructions as prose (must be converted to numbered sub-list):

```markdown
### Step N: Open the palette and add the connector
Click the **+ Add Connection** button to open the palette. Search for the connector and click the connector card to open the form.
```

## Save Location

`artifacts/workflow-docs/[goal-slug]-connector-guide.md`
