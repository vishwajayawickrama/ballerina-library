---
name: connector-workflow
description: Step-by-step workflow for adding a connector to WSO2 Integrator. Covers locating the connector (Category A), configuring connection parameters (Category B), and configuring the primary remote function with Log step (Category C). Use when implementing connector integration stages.
user-invocable: false
---

# WSO2 Connector Workflow

Follow Categories A → B → C in order. Do NOT skip Category C.

## Category A — Locate and Add Connector

### Sub-step 1: Open the connector palette

Click the "Add Connection" button (or "+" in the Connections section) to open the connector search panel.

**Take screenshot 01 IMMEDIATELY** — before typing in the search box or clicking any connector card. The palette must be visible with its search field and connector list.

### Sub-step 2: Search and select

Type the connector name in the search box, locate the connector card, and click it. The connection configuration form opens inline.

**CRITICAL**: After clicking the connector card, do NOT click Save/Add yet. The configuration form is now open — proceed directly to Category B to fill all parameters first.

## Category B — Configure Connection Parameters

This is a CONTINUOUS form interaction. The form was opened at the end of Category A. Do NOT leave the form, save with defaults, and re-open it.

### Rules

- ALL non-boolean fields (required AND optional) MUST be bound to a Configurable variable.
- Boolean fields: select `true` or `false` from the dropdown. Never create a configurable for booleans.
- Do NOT change the default auth type in any connection or Record Configuration form.
- Work field-by-field. Do NOT try to create configurables for multiple fields from the same helper panel session.

Follow the detailed configurable binding workflow from the `lowcode-rules` skill.

### Before Saving — Pre-Save Audit

Scroll the entire form top to bottom. Call `browser_snapshot`. Verify every field shows a configurable reference. Bind any missed fields before saving.

### Take Screenshot 02

After ALL fields are bound, BEFORE saving. Follow the full pre-screenshot checklist from the `screenshot-rules` skill.

The documentation step for this screenshot MUST list every configured parameter as a bullet point:
**[Display Label]** — [one-line description of what this parameter controls]

### Save the Connection

Click Save/Add to persist the connection.

### Verify Canvas and Take Screenshot 03

Call `browser_snapshot` to confirm you are on the **integration design canvas** (title reads "Design", connector node visible on canvas). If you see a project-level file tree or overview page, navigate to the correct canvas first.

Take screenshot 03 showing the connector entry visible in the Connections panel or on the canvas.

## Category C — Configure Primary Remote Function

### Determine the Integration Pattern (from Stage 4 Exploration)

- **Automation pattern**: scheduled/trigger-based — add an Automation entry point, then call the connector inside it.
- **Event Listener pattern**: reactive — add a Listener entry point, call the connector in response.

### PATH 1 — Automation (Scheduled/Trigger-Based) Pattern

If the goal requires calling the connector on a schedule or as a standalone trigger:

1. On the canvas or palette, locate and click **"+ Add Automation"** (or "New Automation") to add an automation entry point.
2. Configure the automation trigger if prompted (e.g., interval — use a safe default like every 1 minute).
3. Inside the automation body/flow, add a new step to call the connector:
   - Look for an **"Add"**, **"+"**, or **"Call"** button within the automation flow.
   - In the left sidebar **Connections** tree, expand the saved connection node to reveal its operations.
   - **Take screenshot 04** after expanding — showing all available operations BEFORE selecting any.
   - Drag or click the primary operation into the automation body.
4. Proceed to "Configure Operation Fields" below.

### PATH 2 — Event Listener Pattern (or Direct Connector Call)

If the goal uses an event listener entry point, or the connector can be called directly:

1. In the left sidebar, locate the **Connections** tree/section.
2. Expand the connection node to reveal its available operations/functions.
   - **Take screenshot 04** after expanding — showing all available operations BEFORE selecting any.
3. Proceed to "Select the Primary Operation" below.

### Select the Primary Operation

Choose the most fundamental write/send operation for this connector type:

| Connector Type | Primary Operation |
|---------------|-------------------|
| Kafka | **Send** |
| MySQL / PostgreSQL / any database | **Insert** or **Execute** |
| Salesforce | **Create** |
| HTTP | **GET** / **POST** |
| Slack / Teams | **PostMessage** |
| Other | Choose the most fundamental write/send operation |

### Configure Operation Fields

1. Click on the selected operation to open its configuration panel.
2. Inspect all available input fields and the Record Configuration panel.
3. Populate fields with a valid, functional data template:

| System Type | Example Data |
|------------|-------------|
| Byte-based (Kafka, MQTT) | `"Hello World".toBytes()` |
| Record-based (DB INSERT) | `{ id: 1, name: "John Doe", email: "john@example.com" }` |
| Key-value (Redis, DynamoDB) | key `"greeting"`, value `"Hello, World!"` |
| REST/HTTP | `{ "message": "Hello, World!", "sender": "integration" }` |
| Salesforce | `{ Name: "Test Account", Industry: "Technology" }` |

4. **Close the Record Configuration modal immediately** after entering values (× or ←).
5. If the operation has a Result/Return Variable field, bind it to a local variable named `result`.

### Take Screenshot 05

After ALL operation fields are populated. Follow the full pre-screenshot checklist from the `screenshot-rules` skill.

### Save the Operation

### Add Log Step (ONLY If `result` Variable Was Bound — Void Operations: Skip Entirely)

**Placement — CRITICAL:**

- Locate the **+** button immediately AFTER the remote function node on the MAIN flow path (between the operation node and End/Stop).
- **FORBIDDEN positions**: before the operation node, inside the On Error/Error Handler branch, after End.
- If ambiguous, hover the operation node via `browser_hover` to highlight the correct insertion handle. Do NOT use `browser_evaluate` to click by index.

**Configure the Log step:**

1. Select **Log Info** from the Logging group.
2. Switch to **Expression** mode (MANDATORY — do NOT use Text mode with a literal string).
3. Enter exactly: `result.toString()` — works for all return types.
4. Press Tab to trigger expression validation. Re-snapshot and confirm no "undefined symbol" error.
5. Close the helper/Variables panel (it intercepts Save clicks if left open).
6. Click **Save**.

**Verify placement:**

- Log node appears on canvas with `result.toString()` (not a literal string).
- Log node is directly connected on the main flow path (operation → Log → End).
- Log node is NOT inside the On Error/Error Handler region.

### Take Screenshot 06

Completed flow: Entry Point → Remote Function → Log (if present) → End.

Follow pre-screenshot checklist. Capture on EVERY run regardless of whether a Log step was added.
