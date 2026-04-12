---
name: playwright-rules
description: Rules for browser automation using Playwright MCP tools. Use whenever interacting with a browser, navigating URLs, clicking elements, filling forms, or performing any web UI interaction via Playwright MCP.
user-invocable: false
---

# Playwright MCP Rules

## Strict Rules (Mandatory)

- **ONLY** interact with the browser through the Playwright MCP server tools (e.g., `browser_navigate`, `browser_click`, `browser_fill`, `browser_snapshot`, `browser_take_screenshot`, `browser_wait_for_idle`, etc.).
- Do **NOT** create, write, or generate any JavaScript (.js) or TypeScript (.ts) Playwright script files.
- Do **NOT** run any Playwright scripts via the terminal (e.g., `npx playwright`, `node script.js`).
- Do **NOT** use `page.route()`, `browser.newContext()`, or any Playwright Node.js API directly.
- All browser interactions must happen through **direct MCP tool calls** — the agent talks to the Playwright MCP server, never writes automation code.
- If a step seems to require writing a script file, **do NOT do it** — use the corresponding Playwright MCP tool instead.

## Navigation Pattern

Your core loop: `browser_snapshot` → analyze → act → `browser_snapshot` (verify) → repeat.

## Waiting and Loading Rules

- After each navigation action, wait for the networkidle state before interacting.
- After each UI click/action, wait **2–5 seconds** for resources to load.
- If a spinner or loading indicator is visible, wait until it disappears.
- If the UI looks blank or partially loaded, wait and retry after **3 seconds**.
- Use `browser_snapshot` to check whether the UI has fully loaded — inspect the DOM tree for expected elements.

## Error Recovery

- If the low-code interface does not load, wait and retry (up to 3 attempts).
- If a UI element is missing or renamed, find it by label, role, or text.
- If persistent failure, ask the user for guidance.
