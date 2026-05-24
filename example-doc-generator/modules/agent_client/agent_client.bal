// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import wso2/example_doc_generator.claude_agent_sdk;
import wso2/example_doc_generator.utils;

public type AgentCost claude_agent_sdk:AgentCost;

const string MODEL = "claude-sonnet-4-6";
const int TIMEOUT_SECONDS = 5400;
const int MAX_BUFFER_SIZE = 33554432;

final string[] ALLOWED_TOOLS = [
    "Bash",
    "Read",
    "Write",
    "Edit",
    "mcp__playwright__browser_navigate",
    "mcp__playwright__browser_navigate_back",
    "mcp__playwright__browser_click",
    "mcp__playwright__browser_type",
    "mcp__playwright__browser_fill_form",
    "mcp__playwright__browser_take_screenshot",
    "mcp__playwright__browser_run_code",
    "mcp__playwright__browser_snapshot",
    "mcp__playwright__browser_evaluate",
    "mcp__playwright__browser_wait_for",
    "mcp__playwright__browser_select_option",
    "mcp__playwright__browser_press_key",
    "mcp__playwright__browser_hover",
    "mcp__playwright__browser_drag",
    "mcp__playwright__browser_tabs",
    "mcp__playwright__browser_close",
    "mcp__playwright__browser_resize",
    "mcp__playwright__browser_handle_dialog",
    "mcp__playwright__browser_file_upload",
    "mcp__playwright__browser_install",
    "mcp__playwright__browser_console_messages",
    "mcp__playwright__browser_network_requests"
];

const string SYSTEM_PROMPT = string `You are a WSO2 Integrator documentation automation agent.

Follow the provided execution prompt as the source of truth. It may describe a
connector workflow or a trigger workflow; adapt your language, screenshots,
artifact names, and documentation structure to the workflow type in that prompt.

Use browser automation for WSO2 Integrator UI work, and use file tools only when
the execution prompt explicitly asks you to inspect or edit generated project
files. Keep generated artifacts under the paths given in the execution prompt.
Do not introduce extra setup notes, environment details, or undocumented
workflow sections beyond what the execution prompt requires.`;

# Initializes the Claude agent SDK wrapper.
#
# + return - nil; preflight checks are performed by main.bal
public function initAgentBridge() returns error? {
}

# Runs Claude Agent SDK from Ballerina using the internal SDK module.
#
# + promptPath - absolute or relative path to the generated execution prompt file
# + return     - AgentCost if available, nil if cost data was absent, or an error
public function runClaudeAgent(string promptPath) returns AgentCost?|error {
    string prompt = check readPrompt(promptPath);
    prompt = addRuntimeCompatibilityInstructions(prompt);

    check ensureAgentArtifactDirs();

    string|error cwdResult = file:getCurrentDir();
    string projectRoot = check cwdResult;
    string claudePath = "claude";
    utils:log("\t[INFO] Claude CLI command: " + claudePath);

    claude_agent_sdk:AgentConfig config = {
        model: MODEL,
        systemPrompt: SYSTEM_PROMPT,
        tools: ALLOWED_TOOLS,
        allowedTools: ALLOWED_TOOLS,
        mcpServers: [
            {
                name: "playwright",
                command: "npx",
                arguments: [
                    "--yes",
                    "@playwright/mcp@latest",
                    "--headless",
                    "--viewport-size=1720,968",
                    "--output-dir=" + projectRoot + "/artifacts/screenshots",
                    "--output-mode",
                    "stdout"
                ]
            }
        ],
        workingDirectory: projectRoot,
        claudePath: claudePath,
        timeoutSeconds: TIMEOUT_SECONDS,
        maxBufferSize: MAX_BUFFER_SIZE,
        permissionMode: "ACCEPT_EDITS"
    };

    claude_agent_sdk:AgentSession session = check claude_agent_sdk:openSession(config, prompt);
    AgentCost? cost = ();
    error? runErr = ();
    do {
        while true {
            claude_agent_sdk:AgentEvent event = check claude_agent_sdk:nextEvent(session);
            if event.'type == "done" {
                utils:log("\t[INFO] Claude agent finished.");
                break;
            }
            if event.'type == "result" {
                logResultEvent(event);
                cost = event.cost;
                continue;
            }
            logAgentEvent(event);
        }
    } on fail error e {
        runErr = e;
    }
    claude_agent_sdk:closeSession(session);
    if runErr is error {
        return runErr;
    }
    return cost;
}

# Releases agent SDK resources.
#
# + return - nil; retained for the existing pipeline lifecycle
public function stopAgentBridge() returns error? {
}

function readPrompt(string promptPath) returns string|error {
    if promptPath.trim() == "" {
        return error("prompt_path required");
    }
    string|io:Error prompt = io:fileReadString(promptPath);
    if prompt is io:Error {
        return error("Could not read prompt file: " + prompt.message());
    }
    return prompt;
}

function ensureAgentArtifactDirs() returns error? {
    file:Error? screenshotErr = file:createDir("./artifacts/screenshots", file:RECURSIVE);
    if screenshotErr is file:Error {
        return error("Could not create screenshots directory: " + screenshotErr.message());
    }
    file:Error? docsErr = file:createDir("./artifacts/workflow-docs", file:RECURSIVE);
    if docsErr is file:Error {
        return error("Could not create workflow docs directory: " + docsErr.message());
    }
}

function addRuntimeCompatibilityInstructions(string prompt) returns string {
    return string `## Runtime Tooling Compatibility

This run is executed through the in-process Ballerina Claude agent SDK wrapper.
Do not look for, start, query, or depend on python/agent_server.py, /health endpoints,
/run endpoints, or any local REST agent server. The Ballerina pipeline has already
launched this agent.

Browser automation tools are exposed as Claude Code MCP tools with names like:
- mcp__playwright__browser_navigate
- mcp__playwright__browser_click
- mcp__playwright__browser_type
- mcp__playwright__browser_snapshot
- mcp__playwright__browser_take_screenshot
- mcp__playwright__browser_wait_for
- mcp__playwright__browser_evaluate

When the execution prompt says browser_navigate, browser_snapshot,
browser_take_screenshot, or similar, call the corresponding
mcp__playwright__... tool directly. Do not use Agent, Task, ToolSearch, WebFetch,
JavaScript automation files, or repository inspection to substitute for browser
tool calls.

${prompt}`;
}

function logAgentEvent(claude_agent_sdk:AgentEvent event) {
    if event.'type == "session" {
        string detail = event.sessionId is string ? "id=" + event.sessionId.toString() :
            "subtype=" + (event.subtype ?: "unknown");
        utils:log("\t[SESSION] " + detail);
        return;
    }
    if event.'type == "system" {
        utils:log("\t[SYSTEM] subtype=" + (event.subtype ?: "unknown"));
        return;
    }
    if event.'type == "assistant_text" {
        utils:log("\t[CLAUDE] " + (event.text ?: ""));
        return;
    }
    if event.'type == "tool_use" {
        utils:log("\t[TOOL] " + (event.name ?: "unknown") + " -> " + truncateToolInput(event.input ?: "", 500));
        return;
    }
    utils:log("\t[" + event.'type.toUpperAscii() + "] " + (event.text ?: ""));
}

function logResultEvent(claude_agent_sdk:AgentEvent event) {
    utils:log("\t[RESULT] " + (event.text ?: ""));
    AgentCost? cost = event.cost;
    if cost is AgentCost {
        utils:log("\t[USAGE] input=" + cost.inputTokens.toString()
            + " output=" + cost.outputTokens.toString()
            + " cache_read=" + cost.cacheReadTokens.toString()
            + " cache_write=" + cost.cacheWriteTokens.toString());
        decimal? totalCost = cost.totalCostUsd;
        if totalCost is decimal {
            utils:log("\t[USAGE] total_cost=$" + totalCost.toString());
        }
        int? turns = cost.numTurns;
        if turns is int {
            utils:log("\t[USAGE] turns=" + turns.toString());
        }
    }
}

function truncateToolInput(string text, int maxLength) returns string {
    if text.length() <= maxLength {
        return text;
    }
    return text.substring(0, maxLength) + "... (truncated, " + text.length().toString() + " total chars)";
}
