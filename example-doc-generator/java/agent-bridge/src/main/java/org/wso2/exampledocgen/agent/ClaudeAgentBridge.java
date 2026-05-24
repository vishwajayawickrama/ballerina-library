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

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

/**
 * Small stable Java facade for Ballerina Java interop.
 */
public final class ClaudeAgentBridge {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final Path PROJECT_ROOT = Path.of("").toAbsolutePath().normalize();
    private static final ExecutorService EXECUTOR = Executors.newCachedThreadPool(runnable -> {
        Thread thread = new Thread(runnable, "claude-agent-bridge");
        thread.setDaemon(true);
        return thread;
    });
    private static final Map<String, Job> JOBS = new ConcurrentHashMap<>();

    private static final String MODEL = "claude-sonnet-4-6";
    private static final String SYSTEM_PROMPT = """
            You are a WSO2 Integrator documentation automation agent.

            Follow the provided execution prompt as the source of truth. It may describe a
            connector workflow or a trigger workflow; adapt your language, screenshots,
            artifact names, and documentation structure to the workflow type in that prompt.

            Use browser automation for WSO2 Integrator UI work, and use file tools only when
            the execution prompt explicitly asks you to inspect or edit generated project
            files. Keep generated artifacts under the paths given in the execution prompt.
            Do not introduce extra setup notes, environment details, or undocumented
            workflow sections beyond what the execution prompt requires.
            """.strip();

    private static final List<String> ALLOWED_TOOLS = List.of(
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
    );

    private ClaudeAgentBridge() {
    }

    public static BString init() {
        return StringUtils.fromString("ok");
    }

    public static BString startRun(BString promptPath) {
        String jobId = UUID.randomUUID().toString();
        Job job = new Job();
        JOBS.put(jobId, job);
        Future<?> future = EXECUTOR.submit(() -> runAgent(job, promptPath.getValue()));
        job.future = future;
        return StringUtils.fromString(jobId);
    }

    public static BString getJob(BString jobId) {
        Job job = JOBS.get(jobId.getValue());
        if (job == null) {
            return StringUtils.fromString("{\"status\":\"error\",\"logs\":[\"[ERROR] job not found\"],\"cost\":null}");
        }
        return StringUtils.fromString(job.toJson());
    }

    public static void cancelRun(BString jobId) {
        Job job = JOBS.get(jobId.getValue());
        if (job != null) {
            job.cancel();
        }
    }

    public static void shutdown() {
        for (Job job : JOBS.values()) {
            job.cancel();
        }
        EXECUTOR.shutdownNow();
    }

    private static void runAgent(Job job, String promptPath) {
        job.status = "running";
        try {
            Path resolved = resolvePrompt(promptPath);
            String prompt = addRuntimeCompatibilityInstructions(Files.readString(resolved));

            Files.createDirectories(PROJECT_ROOT.resolve("artifacts/screenshots"));
            Files.createDirectories(PROJECT_ROOT.resolve("artifacts/workflow-docs"));

            McpServerConfig playwright = new McpServerConfig.McpStdioServerConfig(
                    "/opt/homebrew/bin/playwright-mcp",
                    List.of(
                            "--headless",
                            "--viewport-size=1720,968",
                            "--output-dir=" + PROJECT_ROOT.resolve("artifacts/screenshots"),
                            "--output-mode",
                            "stdout"
                    )
            );

            CLIOptions options = CLIOptions.builder()
                    .model(MODEL)
                    .systemPrompt(SYSTEM_PROMPT)
                    .tools(ALLOWED_TOOLS)
                    .allowedTools(ALLOWED_TOOLS)
                    .mcpServer("playwright", playwright)
                    .permissionMode(PermissionMode.ACCEPT_EDITS)
                    .maxBufferSize(32 * 1024 * 1024)
                    .build();

            String claudePath = resolveClaudePath(job);
            try (ClaudeSyncClient client = ClaudeClient.sync(options)
                    .workingDirectory(PROJECT_ROOT)
                    .claudePath(claudePath)
                    .timeout(Duration.ofMinutes(90))
                    .build()) {
                for (Message message : client.connectAndReceive(prompt)) {
                    if (Thread.currentThread().isInterrupted()) {
                        throw new CancellationException("Agent job was cancelled");
                    }
                    handleMessage(job, message);
                }
            }
            if (!"error".equals(job.status)) {
                job.status = "done";
            }
        } catch (CancellationException e) {
            job.log("ERROR", e.getMessage());
            job.status = "error";
        } catch (Exception e) {
            job.log("ERROR", e.getMessage() == null ? e.toString() : e.getMessage());
            logCauseChain(job, e);
            job.status = "error";
        }
    }

    private static String addRuntimeCompatibilityInstructions(String prompt) {
        return """
                ## Runtime Tooling Compatibility

                This run is executed through the in-process Java Claude agent bridge.
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

                """.strip() + "\n\n" + prompt;
    }

    private static String resolveClaudePath(Job job) throws IOException, InterruptedException {
        String envPath = System.getenv("CLAUDE_CLI_PATH");
        if (envPath != null && !envPath.isBlank() && isWorkingClaudeCommand(Path.of(envPath))) {
            job.log("INFO", "Claude CLI: " + envPath + " (CLAUDE_CLI_PATH)");
            return envPath;
        }

        if (canRunCommand("claude")) {
            job.log("INFO", "Claude CLI: claude (PATH)");
            return "claude";
        }

        String home = System.getProperty("user.home");
        List<Path> candidates = new ArrayList<>();
        candidates.add(Path.of("/opt/homebrew/bin/claude"));
        candidates.add(Path.of("/usr/local/bin/claude"));
        candidates.add(Path.of(home, ".local/bin/claude"));
        candidates.add(Path.of(home, ".npm-global/bin/claude"));
        candidates.add(Path.of(home, ".yarn/bin/claude"));
        candidates.add(Path.of(home, ".bun/bin/claude"));
        candidates.add(Path.of(home, ".nvm/versions/node/latest/bin/claude"));
        candidates.addAll(nvmClaudeCandidates(Path.of(home, ".nvm/versions/node")));

        for (Path candidate : candidates) {
            if (isWorkingClaudeCommand(candidate)) {
                String path = candidate.toString();
                job.log("INFO", "Claude CLI: " + path);
                return path;
            }
        }

        throw new IOException("Claude CLI executable was not found. Install Claude Code CLI, or set CLAUDE_CLI_PATH "
                + "to the absolute path of the claude executable before running the pipeline.");
    }

    private static List<Path> nvmClaudeCandidates(Path nodeVersionsDir) throws IOException {
        if (!Files.isDirectory(nodeVersionsDir)) {
            return List.of();
        }
        try (var stream = Files.list(nodeVersionsDir)) {
            return stream
                    .filter(Files::isDirectory)
                    .sorted(Comparator.reverseOrder())
                    .map(path -> path.resolve("bin/claude"))
                    .toList();
        }
    }

    private static boolean canRunCommand(String command) throws IOException, InterruptedException {
        return runVersionCommand(command);
    }

    private static boolean isWorkingClaudeCommand(Path path) throws IOException, InterruptedException {
        return Files.isRegularFile(path) && Files.isExecutable(path) && runVersionCommand(path.toString());
    }

    private static boolean runVersionCommand(String command) throws IOException, InterruptedException {
        Process process;
        try {
            process = new ProcessBuilder(command, "--version")
                    .redirectErrorStream(true)
                    .start();
        } catch (IOException e) {
            return false;
        }
        boolean exited = process.waitFor(5, java.util.concurrent.TimeUnit.SECONDS);
        if (!exited) {
            process.destroyForcibly();
            return false;
        }
        return process.exitValue() == 0;
    }

    private static void logCauseChain(Job job, Exception exception) {
        Throwable cause = exception.getCause();
        while (cause != null) {
            String message = cause.getMessage();
            if (message != null && !message.isBlank()) {
                job.log("ERROR", cause.getClass().getSimpleName() + ": " + message);
            }
            cause = cause.getCause();
        }
    }

    private static Path resolvePrompt(String promptPath) throws IOException {
        if (promptPath == null || promptPath.isBlank()) {
            throw new IOException("prompt_path required");
        }
        Path resolved = Path.of(promptPath);
        if (!resolved.isAbsolute()) {
            resolved = PROJECT_ROOT.resolve(promptPath);
        }
        resolved = resolved.normalize();
        if (!Files.exists(resolved)) {
            throw new IOException("prompt file not found: " + resolved);
        }
        return resolved;
    }

    private static void handleMessage(Job job, Message message) {
        if (message instanceof SystemMessage systemMessage) {
            Object sessionId = systemMessage.data() == null ? null : systemMessage.data().get("session_id");
            String subtype = systemMessage.subtype() == null ? "unknown" : systemMessage.subtype();
            String label = "init".equals(subtype) ? "SESSION" : "SYSTEM";
            String detail = sessionId == null ? "subtype=" + subtype : "id=" + sessionId;
            job.log(label, detail);
            return;
        }

        if (message instanceof AssistantMessage assistantMessage) {
            for (ContentBlock block : assistantMessage.content()) {
                if (block instanceof TextBlock textBlock) {
                    job.log("CLAUDE", textBlock.text());
                } else if (block instanceof ToolUseBlock toolUseBlock) {
                    job.log("TOOL", toolUseBlock.name() + " \u2192 " + truncateToolInput(toolUseBlock.input(), 500));
                } else {
                    job.log("TOOL", block.getClass().getSimpleName());
                }
            }
            return;
        }

        if (message instanceof ResultMessage resultMessage) {
            job.log("RESULT", resultMessage.result());
            recordCost(job, resultMessage);
        }
    }

    private static void recordCost(Job job, ResultMessage resultMessage) {
        int inputTokens = intFromUsage(resultMessage.usage(), "input_tokens");
        int outputTokens = intFromUsage(resultMessage.usage(), "output_tokens");
        int cacheReadTokens = intFromUsage(resultMessage.usage(), "cache_read_input_tokens");
        int cacheWriteTokens = intFromUsage(resultMessage.usage(), "cache_creation_input_tokens");

        job.log("USAGE", "input=" + inputTokens + " output=" + outputTokens
                + " cache_read=" + cacheReadTokens + " cache_write=" + cacheWriteTokens);
        if (resultMessage.totalCostUsd() != null) {
            job.log("USAGE", String.format("total_cost=$%.6f", resultMessage.totalCostUsd()));
        }
        job.log("USAGE", "turns=" + resultMessage.numTurns());

        Map<String, Object> cost = new LinkedHashMap<>();
        cost.put("totalCostUsd", resultMessage.totalCostUsd());
        cost.put("inputTokens", inputTokens);
        cost.put("outputTokens", outputTokens);
        cost.put("cacheReadTokens", cacheReadTokens);
        cost.put("cacheWriteTokens", cacheWriteTokens);
        cost.put("numTurns", resultMessage.numTurns());
        job.cost = cost;
    }

    private static int intFromUsage(Map<String, Object> usage, String key) {
        if (usage == null) {
            return 0;
        }
        Object value = usage.get(key);
        return value instanceof Number number ? number.intValue() : 0;
    }

    private static String truncateToolInput(Object input, int maxLength) {
        String text;
        try {
            text = input instanceof String ? (String) input : MAPPER.writeValueAsString(input);
        } catch (JsonProcessingException e) {
            text = String.valueOf(input);
        }
        if (text.length() > maxLength) {
            return text.substring(0, maxLength) + "... (truncated, " + text.length() + " total chars)";
        }
        return text;
    }

    private static final class Job {
        private final List<String> logs = new ArrayList<>();
        private volatile String status = "queued";
        private volatile Map<String, Object> cost;
        private volatile Future<?> future;

        private synchronized void log(String label, String text) {
            logs.add("[" + label + "] " + (text == null ? "" : text));
        }

        private void cancel() {
            Future<?> currentFuture = future;
            if (currentFuture != null) {
                currentFuture.cancel(true);
            }
        }

        private synchronized String toJson() {
            Map<String, Object> snapshot = new LinkedHashMap<>();
            snapshot.put("status", status);
            snapshot.put("logs", List.copyOf(logs));
            snapshot.put("cost", cost);
            try {
                return MAPPER.writeValueAsString(snapshot);
            } catch (JsonProcessingException e) {
                return "{\"status\":\"error\",\"logs\":[\"[ERROR] could not serialize job\"],\"cost\":null}";
            }
        }
    }
}
