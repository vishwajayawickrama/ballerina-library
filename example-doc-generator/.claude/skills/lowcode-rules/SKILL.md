---
name: lowcode-rules
description: Strict rules for interacting with WSO2 Integrator low-code UI. Use whenever working with the WSO2 Integrator extension, creating connections, configuring connectors, or filling connection forms in code-server.
user-invocable: false
---

# WSO2 Integrator Low-Code Rules

## Strict Rules (Mandatory)

- Use **only** low-code UI elements (Entry Points, Listeners, Connections, etc.).
- Do **NOT** open or edit any .bal files directly.
- Do **NOT** use "Show Source" or any code/text view.
- Do **NOT** modify code in the editor.
- **If a .bal file tab opens automatically** (e.g., VS Code auto-opens it when creating an integration), **immediately close that editor tab** — click the × on the tab or use Ctrl+W — before proceeding. Do NOT read, inspect, or document its contents.
- **If any source code window or code editor tab is open**, close it before taking any milestone screenshot. Screenshots must never show source code.
- If a step appears to require manual code editing, **stop and request user guidance**.
- Do **NOT** click the **Expression** toggle/button for any connection parameter field — this includes boolean fields. Boolean fields (showing a true/false dropdown) must be set by selecting from the dropdown, never by switching to Expression mode. For non-boolean fields, use the helper panel directly without switching to Expression mode.

## Record Configuration Modal (CRITICAL)

Whenever a "Record Configuration" modal opens (title "Record Configuration", has a `×` close button top-right and a `←` back button top-left):

1. Fill in all required values.
2. **Immediately close it** using the `×` or `←` button before doing anything else.
3. It does **NOT** close on Escape — you must click `×` or `←`.
4. After closing, call `browser_snapshot` to confirm the modal is gone before proceeding.

Do NOT leave the Record Configuration modal open while performing subsequent workflow steps.

## Configurable Binding — NEVER Type Directly Into Fields

**NEVER type a configurable name directly into a field using `browser_type`.**

Typing text into a field creates a Ballerina STRING LITERAL (e.g., `"snowflakeAccountIdentifier"`) not a variable reference. The integration will fail because it passes the literal text as the credential instead of the configured value.

The ONLY correct way to bind a configurable:

1. Click the field you want to configure.
2. Click **Open Helper Panel** next to the field.
3. Click the **Configurables** tab.
4. Click **+ New Configurable**.
5. Enter Variable Name (camelCase), Variable Type (`string` for text/URLs, `int` for ports).
6. Leave Default Value blank for sensitive values.
7. Click **Save** — the configurable is AUTOMATICALLY injected into the field.
8. Do NOT click the configurable name again — it is already bound. Close the helper panel immediately.
9. Move to the next field and repeat from step 1.

**Recovery — if the wrong configurable was injected:**
Open THAT field's helper panel → Configurables tab → click the CORRECT configurable name in the list to replace the current value.

## Boolean Fields

Do NOT create configurables for boolean fields. Select `true` or `false` from the dropdown as appropriate for the default/recommended value. Never switch a boolean dropdown to Expression mode.

## Record-Typed Fields (Record Configuration Modal)

Some fields are records — clicking them opens the Record Configuration modal. Inside this modal:

- The nested sub-fields do NOT have an "Open Helper Panel" button.
- Use the right-side code-preview textbox instead:
  1. Click the value position of the FIRST sub-field line (between the quotes).
  2. A helper panel appears below the preview.
  3. Click Configurables → + New Configurable → fill Name and Type → Save.
  4. Verify the preview line now shows an identifier (e.g., `refreshUrl: refreshUrl,`) not `""`.
  5. Move to the NEXT sub-field and repeat. One sub-field at a time.
- After ALL sub-fields are bound (no empty strings), close the modal via × or ←.

## Auth Fields in Record Configuration

If the Record Configuration panel contains an auth-type union field (e.g., a dropdown showing `OAuth2ClientCredentialsGrantConfig`, `CredentialsConfig`, `BearerTokenConfig`, etc.):

- **Do NOT change the selected auth type.** Leave the default selection as-is.
- Only fill in the required fields that are already visible under the pre-selected auth type.

## Optional Fields in Record Configuration

Do NOT enable or check any checkbox next to fields labelled "(Optional)". Only interact with fields that are already checked/required.

## Pre-Save Audit (MANDATORY)

Before clicking Save/Add, scroll the entire connection form from top to bottom and call `browser_snapshot`. Verify that EVERY field — including any that appeared collapsed, optional, or greyed-out — now shows a configurable variable reference. If any field is still empty, bind it to a new configurable before proceeding.
