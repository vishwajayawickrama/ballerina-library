// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package org.wso2.exampledocgen.agent;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BString;
import org.springaicommunity.claude.agent.sdk.ClaudeClient;
import org.springaicommunity.claude.agent.sdk.ClaudeSyncClient;
import org.springaicommunity.claude.agent.sdk.config.PermissionMode;
import org.springaicommunity.claude.agent.sdk.mcp.McpServerConfig;
import org.springaicommunity.claude.agent.sdk.transport.CLIOptions;
import org.springaicommunity.claude.agent.sdk.types.AssistantMessage;
import org.springaicommunity.claude.agent.sdk.types.ContentBlock;
import org.springaicommunity.claude.agent.sdk.types.Message;
import org.springaicommunity.claude.agent.sdk.types.ResultMessage;
import org.springaicommunity.claude.agent.sdk.types.SystemMessage;
import org.springaicommunity.claude.agent.sdk.types.TextBlock;
import org.springaicommunity.claude.agent.sdk.types.ToolUseBlock;

import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Queue;

/**
 * Thin Java adapter for Ballerina Java interop over the Claude Agent SDK.
 */
public final class ClaudeAgentBridge {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private ClaudeAgentBridge() {
    }

    public static Object openSession(BString configJson, BString prompt) {
        try {
            Map<String, Object> config = MAPPER.readValue(configJson.getValue(), new TypeReference<>() {
            });
            CLIOptions options = buildOptions(config);
            String workingDirectory = requiredString(config, "workingDirectory");
            String claudePath = requiredString(config, "claudePath");
            int timeoutSeconds = intValue(config, "timeoutSeconds", 5400);

            ClaudeSyncClient client = ClaudeClient.sync(options)
                    .workingDirectory(Path.of(workingDirectory))
                    .claudePath(claudePath)
                    .timeout(Duration.ofSeconds(timeoutSeconds))
                    .build();
            Iterable<Message> messages = client.connectAndReceive(prompt.getValue());
            return new AgentSession(client, messages.iterator());
        } catch (Exception e) {
            return new FailedSession(e);
        }
    }

    public static BString nextEvent(Object sessionHandle) {
        if (sessionHandle instanceof FailedSession failedSession) {
            return errorEvent(failedSession.exception());
        }
        if (!(sessionHandle instanceof AgentSession session)) {
            return errorEvent(new IllegalArgumentException("Invalid Claude Agent SDK session handle"));
        }
        try {
            if (!session.pendingEvents().isEmpty()) {
                return toJson(session.pendingEvents().remove());
            }
            if (!session.messages().hasNext()) {
                return event("done", Map.of());
            }
            Message message = session.messages().next();
            List<Map<String, Object>> events = normalizeMessage(message);
            if (events.isEmpty()) {
                return event("system", Map.of("subtype", message.getClass().getSimpleName()));
            }
            session.pendingEvents().addAll(events);
            return toJson(session.pendingEvents().remove());
        } catch (Exception e) {
            return errorEvent(e);
        }
    }

    public static void closeSession(Object sessionHandle) {
        if (sessionHandle instanceof AgentSession session) {
            session.client().close();
        }
    }

    private static CLIOptions buildOptions(Map<String, Object> config) {
        CLIOptions.Builder builder = CLIOptions.builder()
                .model(requiredString(config, "model"))
                .systemPrompt(requiredString(config, "systemPrompt"))
                .tools(stringList(config.get("tools")))
                .allowedTools(stringList(config.get("allowedTools")))
                .permissionMode(PermissionMode.valueOf(stringValue(config, "permissionMode", "ACCEPT_EDITS")))
                .maxBufferSize(intValue(config, "maxBufferSize", 32 * 1024 * 1024));

        for (Map<String, Object> mcpServer : mapList(config.get("mcpServers"))) {
            String name = requiredString(mcpServer, "name");
            String command = requiredString(mcpServer, "command");
            List<String> arguments = stringList(mcpServer.get("arguments"));
            builder.mcpServer(name, new McpServerConfig.McpStdioServerConfig(command, arguments));
        }
        return builder.build();
    }

    private static List<Map<String, Object>> normalizeMessage(Message message) {
        List<Map<String, Object>> events = new ArrayList<>();
        if (message instanceof SystemMessage systemMessage) {
            Object sessionId = systemMessage.data() == null ? null : systemMessage.data().get("session_id");
            Map<String, Object> event = new LinkedHashMap<>();
            event.put("type", "init".equals(systemMessage.subtype()) ? "session" : "system");
            event.put("subtype", systemMessage.subtype() == null ? "unknown" : systemMessage.subtype());
            if (sessionId != null) {
                event.put("sessionId", sessionId.toString());
            }
            events.add(event);
            return events;
        }

        if (message instanceof AssistantMessage assistantMessage) {
            for (ContentBlock block : assistantMessage.content()) {
                if (block instanceof TextBlock textBlock) {
                    events.add(Map.of("type", "assistant_text", "text", textBlock.text()));
                } else if (block instanceof ToolUseBlock toolUseBlock) {
                    Map<String, Object> event = new LinkedHashMap<>();
                    event.put("type", "tool_use");
                    event.put("name", toolUseBlock.name());
                    event.put("input", jsonOrString(toolUseBlock.input()));
                    events.add(event);
                } else {
                    events.add(Map.of("type", "tool_use", "name", block.getClass().getSimpleName(), "input", ""));
                }
            }
            return events;
        }

        if (message instanceof ResultMessage resultMessage) {
            Map<String, Object> event = new LinkedHashMap<>();
            event.put("type", "result");
            event.put("text", resultMessage.result());
            event.put("cost", cost(resultMessage));
            events.add(event);
        }
        return events;
    }

    private static Map<String, Object> cost(ResultMessage resultMessage) {
        Map<String, Object> cost = new LinkedHashMap<>();
        cost.put("totalCostUsd", resultMessage.totalCostUsd());
        cost.put("inputTokens", intFromUsage(resultMessage.usage(), "input_tokens"));
        cost.put("outputTokens", intFromUsage(resultMessage.usage(), "output_tokens"));
        cost.put("cacheReadTokens", intFromUsage(resultMessage.usage(), "cache_read_input_tokens"));
        cost.put("cacheWriteTokens", intFromUsage(resultMessage.usage(), "cache_creation_input_tokens"));
        cost.put("numTurns", resultMessage.numTurns());
        return cost;
    }

    private static int intFromUsage(Map<String, Object> usage, String key) {
        if (usage == null) {
            return 0;
        }
        Object value = usage.get(key);
        return value instanceof Number number ? number.intValue() : 0;
    }

    private static BString event(String type, Map<String, Object> fields) {
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("type", type);
        event.putAll(fields);
        return toJson(event);
    }

    private static BString errorEvent(Exception exception) {
        String message = exception.getMessage() == null ? exception.toString() : exception.getMessage();
        return event("error", Map.of("text", message));
    }

    private static BString toJson(Map<String, Object> event) {
        try {
            return StringUtils.fromString(MAPPER.writeValueAsString(event));
        } catch (JsonProcessingException e) {
            return StringUtils.fromString("{\"type\":\"error\",\"text\":\"Could not serialize Claude Agent SDK event\"}");
        }
    }

    private static String jsonOrString(Object input) {
        try {
            return input instanceof String ? (String) input : MAPPER.writeValueAsString(input);
        } catch (JsonProcessingException e) {
            return String.valueOf(input);
        }
    }

    private static String requiredString(Map<String, Object> values, String key) {
        Object value = values.get(key);
        if (value instanceof String text && !text.isBlank()) {
            return text;
        }
        throw new IllegalArgumentException(key + " is required");
    }

    private static String stringValue(Map<String, Object> values, String key, String defaultValue) {
        Object value = values.get(key);
        return value instanceof String text && !text.isBlank() ? text : defaultValue;
    }

    private static int intValue(Map<String, Object> values, String key, int defaultValue) {
        Object value = values.get(key);
        return value instanceof Number number ? number.intValue() : defaultValue;
    }

    private static List<String> stringList(Object value) {
        if (!(value instanceof List<?> list)) {
            return List.of();
        }
        return list.stream().map(String::valueOf).toList();
    }

    private static List<Map<String, Object>> mapList(Object value) {
        if (!(value instanceof List<?> list)) {
            return List.of();
        }
        List<Map<String, Object>> result = new ArrayList<>();
        for (Object item : list) {
            if (item instanceof Map<?, ?> map) {
                Map<String, Object> typed = new LinkedHashMap<>();
                for (Map.Entry<?, ?> entry : map.entrySet()) {
                    typed.put(String.valueOf(entry.getKey()), entry.getValue());
                }
                result.add(typed);
            }
        }
        return result;
    }

    private record AgentSession(ClaudeSyncClient client, Iterator<Message> messages,
                                Queue<Map<String, Object>> pendingEvents) {
        private AgentSession(ClaudeSyncClient client, Iterator<Message> messages) {
            this(client, messages, new ArrayDeque<>());
        }
    }

    private record FailedSession(Exception exception) {
    }
}
