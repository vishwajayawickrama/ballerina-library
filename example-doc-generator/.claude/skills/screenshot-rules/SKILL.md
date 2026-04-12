---
name: screenshot-rules
description: Rules for when and how to take screenshots during WSO2 Integrator connector workflows. Use whenever taking browser screenshots, naming screenshot files, or documenting UI milestones with browser_take_screenshot.
user-invocable: false
---

# Screenshot Rules

## Snapshot vs Screenshot (Mandatory)

- **`browser_snapshot`** — use for ALL navigation and decision-making. Returns the DOM accessibility tree. Fast, lightweight. Use freely.
- **`browser_take_screenshot`** — for documentation milestones ONLY. Ask: "Would a reader need to see this to reproduce the workflow?" Only capture if yes.
- **NEVER use `browser_take_screenshot` to analyze or understand the UI.** Screenshots incur heavy vision-model processing overhead.

## 6 Mandatory Screenshots — Capture in This Order

| # | Moment | Filename Pattern |
|---|--------|-----------------|
| 01 | Connector palette open — BEFORE typing in search box or selecting any connector | `[prefix]_screenshot_01_palette.png` |
| 02 | Connection form filled — ALL fields bound to configurables, BEFORE saving | `[prefix]_screenshot_02_connection_form.png` |
| 03 | Canvas/Connections panel after save — connector visible | `[prefix]_screenshot_03_connections_list.png` |
| 04 | Operations panel expanded — ALL operations visible, BEFORE selecting any | `[prefix]_screenshot_04_operations_panel.png` |
| 05 | Operation values filled — ALL fields populated, BEFORE or AFTER saving | `[prefix]_screenshot_05_operation_filled.png` |
| 06 | Completed flow on canvas — full chain visible (Entry Point → Remote Function → Log → End) | `[prefix]_screenshot_06_completed_flow.png` |

- Use the **screenshot prefix provided in the execution prompt** as `[prefix]` for ALL screenshot filenames in this run.
- Target 6–7 total. You may capture 1 additional beyond the 6 only if genuinely valuable.
- A step may have zero, one, or multiple screenshots — there is no per-step requirement.

## Filename Format

`[prefix]_screenshot_NN.png` or `[prefix]_screenshot_NN_suffix.png`

- Numbers must be sequential across the entire run.
- The `filename` parameter MUST always be set — never call `browser_take_screenshot` without it.

## Screenshot Ordering (MANDATORY)

Screenshots MUST appear in documentation in ascending filename-number order. NEVER embed a higher-numbered screenshot before a lower-numbered one.

## Pre-Screenshot Checklist (MANDATORY — Run Before EVERY `browser_take_screenshot`)

### Step 1 — Close ALL Overlays

Call `browser_snapshot` to inspect what is visible. Close:

- **Record Configuration modal** (title "Record Configuration", `×` top-right or `←` top-left — does NOT close on Escape): click `×` or `←`, then `browser_snapshot` to confirm dismissed.
- **Configurables/helper side panel**: press Escape or click its close button to dismiss.

After closing, call `browser_snapshot` and verify ONLY the target form/canvas is visible — no overlapping panels, modals, or popovers.

### Step 2 — Scroll to Top

Call `browser_evaluate` to set the scrollable container's `scrollTop` to 0. Target the form panel, sidebar, or canvas panel (whichever applies).

Example: `document.querySelector('[class*="form-panel"], [class*="scrollable"]').scrollTop = 0`

Adapt the selector based on what `browser_snapshot` reveals.

**For screenshot 05**: scroll BOTH the left operation form container AND the right preview panel to top.

### Step 3 — Verify

Call `browser_snapshot` and confirm:
- No helper panel or popover overlapping the form/canvas.
- Topmost fields/nodes are visible at the top of the view.

### Step 4 — Only Then Call `browser_take_screenshot`

## Screenshot-Specific Placement Rules

- **Screenshot 01** (palette): embed ONLY in the sub-step that describes opening the palette. NOT in the search/select sub-step.
- **Screenshot 02** (connection form): embed in the sub-step that describes filling parameters, NOT in opening the form or saving.
- **Screenshot 03** (canvas after save): embed in the sub-step that describes saving the connection / confirming connector on canvas.
- **Screenshot 04** (operations panel): embed in the step that describes expanding the connection node. NOT in selecting or configuring an operation.
- **Screenshot 05** (operation filled): embed in the step that describes selecting the operation AND filling its values.
- **Screenshot 06** (completed flow): embed after the operation save step.

## WSO2 UI Label Extraction (for Documentation)

Use the VISUAL LABEL TEXT rendered above the field in the UI, NOT the configurable variable name.

**How to find it in the accessibility tree:**

1. Find the `textbox` or `combobox` for the field.
2. Navigate UP to the field's outer `generic` container.
3. Inside that container, find the FIRST `generic` child node with plain text — not `"*"` and not a type like `"string"` or `"int"`.
4. That text is the visual label.

**Exception:** If a `textbox` has an accessible name like `textbox "Result*Name of the result variable"`, use the text BEFORE the `*` → **Result**.

**Examples:** `generic: "Service URL"` → **Service URL** | `generic: "Client ID"` → **Client ID** | `generic: "Payload"` → **Payload**

NEVER use the configurable variable name you created (e.g., `zoomServiceUrl`, `kafkaBrokerUrl`) as the documentation label.
