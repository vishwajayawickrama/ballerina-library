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

# Stdio MCP server configuration used by the Claude Agent SDK.
public type McpServerConfig record {|
    # Logical MCP server name.
    string name;
    # Executable command.
    string command;
    # Command-line arguments.
    string[] arguments = [];
|};

# Claude Agent SDK session configuration.
public type AgentConfig record {|
    # Claude model name.
    string model;
    # System prompt passed to the Claude Agent SDK.
    string systemPrompt;
    # Tool names exposed to the model.
    string[] tools = [];
    # Tool names allowed without additional filtering.
    string[] allowedTools = [];
    # MCP servers to register with the SDK.
    McpServerConfig[] mcpServers = [];
    # Working directory for Claude Code execution.
    string workingDirectory;
    # Claude CLI executable path or command.
    string claudePath;
    # SDK client timeout in seconds.
    int timeoutSeconds = 5400;
    # SDK max buffer size in bytes.
    int maxBufferSize = 33554432;
    # Java SDK permission mode enum name, e.g. ACCEPT_EDITS.
    string permissionMode = "ACCEPT_EDITS";
|};

# Structured cost data returned by the Claude Agent SDK.
public type AgentCost record {|
    # Total USD cost reported by the Claude Agent SDK.
    decimal? totalCostUsd = ();
    # Input tokens consumed across the agent run.
    int inputTokens = 0;
    # Output tokens generated across the agent run.
    int outputTokens = 0;
    # Cache read tokens.
    int cacheReadTokens = 0;
    # Cache write tokens.
    int cacheWriteTokens = 0;
    # Number of turns in the agent run.
    int? numTurns = ();
|};

# Normalized event returned by the Java SDK adapter.
public type AgentEvent record {|
    # Event type: session, system, assistant_text, tool_use, result, done, or error.
    string 'type;
    # System event subtype.
    string? subtype = ();
    # Claude session id, if present.
    string? sessionId = ();
    # Text payload for assistant/result/error events.
    string? text = ();
    # Tool name for tool_use events.
    string? name = ();
    # JSON-encoded tool input for tool_use events.
    string? input = ();
    # Final cost for result events.
    AgentCost? cost = ();
|};

# Opaque Java SDK session handle.
public type AgentSession handle;
