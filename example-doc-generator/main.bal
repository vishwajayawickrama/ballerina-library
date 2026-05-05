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
import ballerina/os;
import ballerina/time;

import wso2/example_doc_generator.agent_client;
import wso2/example_doc_generator.ai_client;
import wso2/example_doc_generator.prompts;
import wso2/example_doc_generator.utils;

# Entry point for the full automation pipeline.
#
# Phase 1  (Steps 1–3):  Pre-flight validation — API key, agent auth mode, and Claude Code CLI.
# Phase 2  (Steps 4–7):  Infrastructure     — code-server, extension check, and Python agent server.
# Phase 3  (Steps 8–11): Prompt generation  — build, call Claude, format, save.
# Phase 4  (Steps 12–13): Agent execution   — run agent, enforce doc structure.
# Phase 5  (Steps 14–17): Post-processing   — inject sections, crop screenshots, write run log.
#
# Default mode is connector generation:
#   bal run -- mysql
# Agent API-key mode is opt-in:
#   bal run -- --agent-api-key mysql
# Trigger mode is explicit:
#   bal run -- -t trigger.github ballerinax/trigger.github
#
# + args - connector args by default, or trigger args after -t
# + return                 - an error if any step fails
public function main(string... args) returns error? {
    if args.length() > 0 && args[0] == "crop-screenshots" {
        boolean dryRun = false;
        boolean backup = false;
        foreach string arg in args {
            if arg == "dry-run" {
                dryRun = true;
            } else if arg == "backup" {
                backup = true;
            }
        }
        check utils:cropScreenshots(dryRun, backup);
        return;
    }

    utils:log("=== WSO2 Integrator Documentation Pipeline ===");
    utils:log("");

    boolean useAgentApiKey = false;
    string[] pipelineArgs = [];
    foreach string arg in args {
        if arg == "--agent-api-key" {
            useAgentApiKey = true;
        } else {
            pipelineArgs.push(arg);
        }
    }

    if pipelineArgs.length() == 0 {
        return error("Usage: bal run -- [--agent-api-key] <connector-name> [additional-instructions]\n" +
                     "Trigger mode: bal run -- [--agent-api-key] -t <trigger-name> [trigger-package] [additional-instructions]");
    }

    boolean triggerMode = pipelineArgs[0] == "-t";
    int firstValueIndex = triggerMode ? 1 : 0;
    if pipelineArgs.length() <= firstValueIndex {
        return error("Missing " + (triggerMode ? "trigger" : "connector") + " name.");
    }

    string targetName = pipelineArgs[firstValueIndex];
    string resolvedPackage = "";
    string additionalInstructions = "";
    if triggerMode {
        string defaultPackage = "ballerinax/" + targetName;
        if pipelineArgs.length() > firstValueIndex + 1 {
            string secondArg = pipelineArgs[firstValueIndex + 1];
            if utils:isTriggerPackageArg(secondArg) {
                resolvedPackage = secondArg;
                additionalInstructions = pipelineArgs.length() > firstValueIndex + 2 ? pipelineArgs[firstValueIndex + 2] : "";
            } else {
                resolvedPackage = defaultPackage;
                additionalInstructions = secondArg;
            }
        } else {
            resolvedPackage = defaultPackage;
        }
    } else {
        additionalInstructions = pipelineArgs.length() > firstValueIndex + 1 ? pipelineArgs[firstValueIndex + 1] : "";
    }

    time:Utc startTime = time:utcNow();
    utils:log("[INFO] Start time: " + time:utcToString(startTime));
    utils:log("[INFO] Mode: " + (triggerMode ? "trigger" : "connector"));
    utils:log("[INFO] " + (triggerMode ? "Trigger" : "Connector") + ": " + targetName);
    if triggerMode {
        utils:log("[INFO] Package: " + resolvedPackage);
    }
    utils:log("[INFO] Agent auth mode: " + (useAgentApiKey ? "api-key" : "subscription"));
    if additionalInstructions != "" {
        utils:log("[INFO] Additional instructions: " + additionalInstructions);
    }
    utils:log("");

    // Track LLM usage across all direct API calls (agent cost is tracked separately)
    ai_client:LlmUsage promptGenUsage    = {inputTokens: 0, outputTokens: 0, costUsd: 0.0d};
    ai_client:LlmUsage docEnfUsage       = {inputTokens: 0, outputTokens: 0, costUsd: 0.0d};

    // ── Phase 1: Pre-flight validation ─────────────────────────────────────

    // Step 1: Validate Anthropic API key with a small ping before doing anything else
    utils:log("[STEP 1] Validating Anthropic API key...");
    check ai_client:validateApiKey(anthropicApiKey);
    utils:log("");

    // Step 2: Choose agent auth mode. Ballerina direct API calls still use anthropicApiKey.
    utils:log("[STEP 2] Selecting Python agent auth mode...");
    utils:log("\t[INFO] Agent server auth mode: " + (useAgentApiKey ? "api-key" : "subscription"));
    if useAgentApiKey {
        utils:log("\t[INFO] ANTHROPIC_API_KEY will be passed only to the agent server process.");
    } else {
        utils:log("\t[INFO] ANTHROPIC_API_KEY will not be set by the pipeline for the agent server.");
    }
    utils:log("");

    // Step 3: Check Claude Code CLI is installed (required for agent execution)
    utils:log("[STEP 3] Checking if Claude Code CLI is installed...");
    boolean claudeInstalled = utils:checkClaudeCodeInstalled();
    if !claudeInstalled {
        return error("Claude Code CLI ('claude') is not installed or not on PATH. " +
                     "Install it from https://claude.ai/code and re-run the pipeline.");
    }
    utils:log("\t[INFO] Claude Code CLI is installed.");
    utils:log("");

    // ── Phase 2: Infrastructure ─────────────────────────────────────────────

    // Step 4: Check if code-server binary is installed; install via official script if not
    utils:log("[STEP 4] Checking if code-server is installed...");
    boolean codeServerBinaryInstalled = utils:checkCodeServerInstalled();
    if !codeServerBinaryInstalled {
        utils:log("\t[INFO] code-server not found. Installing via official script (curl -fsSL https://code-server.dev/install.sh | sh)...");
        check utils:installCodeServer();
        utils:log("\t[INFO] code-server installed successfully.");
    } else {
        utils:log("\t[INFO] code-server is already installed.");
    }
    utils:log("");

    // Step 5: Verify code-server is running on the configured port, start if needed
    utils:log("[STEP 5] Verifying code-server on port " + codeServerPort.toString() + "...");
    boolean codeServerRunning = utils:checkCodeServerRunning(codeServerPort);
    if !codeServerRunning {
        utils:log("\t[INFO] Code-server not running. Starting code-server...");
        check utils:startCodeServer(codeServerPort);
        utils:log("\t[INFO] Code-server started successfully.");
    } else {
        utils:log("\t[INFO] Code-server is already running.");
    }
    string codeServerUrl = "http://localhost:" + codeServerPort.toString();
    utils:log("\t[INFO] Code-server URL: " + codeServerUrl);
    utils:log("");

    // Step 6: Ensure the WSO2 Integrator extension is installed in code-server
    utils:log("[STEP 6] Checking WSO2 Integrator extension (wso2.wso2-integrator)...");
    boolean extInstalled = utils:checkExtensionInstalled("wso2.wso2-integrator");
    if !extInstalled {
        utils:log("\t[INFO] Extension not found. Installing from marketplace...");
        check utils:ensureExtensionInstalled("wso2.wso2-integrator");
        utils:log("\t[INFO] Extension installed successfully.");
    } else {
        utils:log("\t[INFO] WSO2 Integrator extension is already installed.");
    }
    utils:log("");

    // Step 7: Check if the Python agent server is running; start it if not
    utils:log("[STEP 7] Checking Python agent server on port " + agentServerPort.toString() + "...");
    boolean agentRunning = utils:checkAgentServerRunning(agentServerPort);
    if !agentRunning {
        utils:log("\t[INFO] Agent server not running. Starting via `uv run agent_server.py`...");
        check utils:startAgentServer(agentServerPort, anthropicApiKey, useAgentApiKey);
        utils:log("\t[INFO] Agent server started.");
    } else {
        utils:log("\t[INFO] Agent server is already running. Restart it to change agent auth mode.");
    }
    string agentUrl = "http://localhost:" + agentServerPort.toString();
    utils:log("\t[INFO] Agent server URL: " + agentUrl);
    utils:log("");

    // ── Phase 3: Prompt generation ──────────────────────────────────────────

    // Derive slug from connector/trigger name — no LLM call needed.
    string nameSlug = targetName.trim().toLowerAscii();
    nameSlug = re `\s+`.replaceAll(nameSlug, "-");
    nameSlug = re `[^a-z0-9\-\.]`.replaceAll(nameSlug, "");

    // Trigger project names cannot contain dots; connector paths preserve them.
    string sampleName = triggerMode ? re `^trigger\.`.replaceAll(nameSlug, "") : nameSlug;
    if triggerMode {
        sampleName = re `\.`.replaceAll(sampleName, "");
    }
    string imgSlug = re `\.`.replaceAll(sampleName, "_");
    string goalSlug = sampleName + (triggerMode ? "-trigger-example" : "-connector-example");
    utils:log("[INFO] " + (triggerMode ? "Trigger" : "Connector") + " slug: " + goalSlug);

    // Write connector/trigger name to artifacts/run-log/ for downstream steps.
    string runLogDir = "./artifacts/run-log";
    file:Error? cnDirErr = file:createDir(runLogDir, file:RECURSIVE);
    if cnDirErr is file:Error {
        return error("Could not create run-log directory: " + cnDirErr.message());
    }
    string nameFile = triggerMode ? "trigger-name.txt" : "connector-name.txt";
    io:Error? cnWriteErr = io:fileWriteString(runLogDir + "/" + nameFile, targetName.trim());
    if cnWriteErr is io:Error {
        return error("Could not write " + nameFile + ": " + cnWriteErr.message());
    }
    utils:log("\t[INFO] " + (triggerMode ? "Trigger" : "Connector") + " name saved to " + runLogDir + "/" + nameFile);
    utils:log("");

    // Step 8: Build system and user prompts
    utils:log("[STEP 8] Building system and user prompts...");
    string|error cwdResult = file:getCurrentDir();
    string projectRoot = cwdResult is string ? cwdResult : os:getEnv("PWD");
    string systemPrompt = triggerMode ?
        prompts:buildTriggerSystemPrompt(projectRoot, targetName, resolvedPackage, imgSlug, sampleName) :
        prompts:buildSystemPrompt(projectRoot, targetName, imgSlug);
    string userMessage = triggerMode ?
        prompts:buildTriggerUserMessage(targetName, resolvedPackage, codeServerUrl, projectRoot, additionalInstructions) :
        prompts:buildUserMessage(targetName, codeServerUrl, projectRoot, additionalInstructions);

    // Step 9: Call Anthropic API to generate the execution prompt
    utils:log("[STEP 9] Calling Anthropic API to generate execution prompt...");
    ai_client:LlmResult promptResult = check ai_client:callClaude(systemPrompt, userMessage, anthropicApiKey);
    string executionPrompt = promptResult.text;
    promptGenUsage = promptResult.usage;

    // Step 10: Add header to the generated prompt
    utils:log("[STEP 10] Formatting execution prompt...");
    string header = string `# Execution Prompt

<!-- ============================================================
     XML-TAGGED MARKDOWN EXECUTION PROMPT
     Generated by: WSO2 Integrator Documentation Pipeline
     Agent: Playwright MCP (Browser Automation)
     Target: Code-Server — WSO2 Integrator (Low-Code)
     ${triggerMode ? "Trigger" : "Connector"}: ${targetName}
     ${triggerMode ? "Package: " + resolvedPackage : ""}
     ============================================================ -->

`;
    string fullPrompt = header + executionPrompt;

    // Step 11: Save to file — returns the path used for the agent in Step 12
    utils:log("[STEP 11] Saving execution prompt to " + utils:OUTPUT_DIR + "...");
    string promptPath = check utils:saveExecutionPrompt(fullPrompt, goalSlug);
    utils:log("\t[INFO] Saved to: " + promptPath);
    utils:log("");

    // ── Phase 4: Agent execution ─────────────────────────────────────────────

    // Step 12: Submit the execution prompt to the agent server and stream logs.
    // If the agent returns a near-empty result (e.g. < 3 turns and no workflow doc
    // written — typically a meta-confusion refusal), retry once before moving on.
    utils:log("[STEP 12] Running Claude agent...");
    agent_client:AgentCost? agentCost = check agent_client:runClaudeAgent(promptPath, agentUrl);

    string workflowDocsDirCheck = "./artifacts/workflow-docs";
    boolean hasWorkflowDoc = false;
    file:MetaData[]|file:Error preEnforceEntries = file:readDir(workflowDocsDirCheck);
    if preEnforceEntries is file:MetaData[] {
        foreach file:MetaData entry in preEnforceEntries {
            if entry.absPath.endsWith(".md") {
                hasWorkflowDoc = true;
                break;
            }
        }
    }
    int? turnCount = ();
    if agentCost is agent_client:AgentCost {
        turnCount = agentCost.numTurns;
    }
    boolean lowTurnRefusal = turnCount is int && turnCount < 3;
    if !hasWorkflowDoc && lowTurnRefusal {
        utils:log("\t[WARN] Agent returned without writing a workflow doc and only " +
                  (turnCount is int ? turnCount.toString() : "?") +
                  " turn(s) — likely a refusal/meta-confusion. Retrying once.");
        agentCost = check agent_client:runClaudeAgent(promptPath, agentUrl);
    }
    utils:log("");

    // ── Phase 5: Post-processing ──────────────────────────────────────────────

    // Step 13: Enforce documentation structure via a dedicated Claude API call.
    // The agent writes the doc with all browser-automation context in its window;
    // rules stated early in the system prompt get buried. This call has the rules
    // fresh in context with no other noise, so they are reliably applied.
    utils:log("[STEP 13] Enforcing documentation structure...");
    string workflowDocsDir = "./artifacts/workflow-docs";
    string enforcedDocPath = "";
    file:MetaData[]|file:Error dirEntries = file:readDir(workflowDocsDir);
    if dirEntries is file:MetaData[] {
        file:MetaData? latestEntry = ();
        foreach file:MetaData entry in dirEntries {
            if entry.absPath.endsWith(".md") {
                if latestEntry is () || time:utcDiffSeconds(entry.modifiedTime, latestEntry.modifiedTime) > 0d {
                    latestEntry = entry;
                }
            }
        }
        string docPath = latestEntry is file:MetaData ? latestEntry.absPath : "";
        if docPath == "" {
            return error("No .md file found in " + workflowDocsDir + " — enforcement cannot proceed.");
        } else {
            utils:log("\t[INFO] Found workflow doc: " + docPath);
            string|io:Error rawDoc = io:fileReadString(docPath);
            if rawDoc is io:Error {
                return error("Could not read workflow doc: " + rawDoc.message());
            }
            enforcedDocPath = docPath;
            string enforcementSystemPrompt = prompts:buildDocEnforcementSystemPrompt();
            ai_client:LlmResult enfResult = check ai_client:callClaude(enforcementSystemPrompt, rawDoc, anthropicApiKey);
            io:Error? writeErr = io:fileWriteString(docPath, enfResult.text);
            if writeErr is io:Error {
                return error("Could not write enforced doc: " + writeErr.message());
            }
            docEnfUsage = enfResult.usage;
            utils:log("\t[INFO] Documentation structure enforced successfully.");
        }
    } else {
        return error("Workflow docs directory not found: " + workflowDocsDir);
    }
    utils:log("");

    // Step 14: Append the "Try it yourself" section (Devant button + GitHub
    // source link). Runs AFTER enforcement so the enforcement prompt's fixed
    // section list does not strip the appended H2.
    utils:log("[STEP 14] Injecting 'Try it yourself' section into workflow doc...");
    utils:injectTryItYourselfSection(enforcedDocPath);
    utils:log("");

    // Step 15: Connector docs also get a Ballerina Central examples link.
    if !triggerMode {
        utils:log("[STEP 15] Checking Ballerina Central for connector examples link...");
        utils:appendExamplesSection(enforcedDocPath);
        utils:log("");
    }

    // Step 16: Crop UI chrome from screenshots produced by the agent
    utils:log("[STEP 16] Cropping screenshots...");
    check utils:cropScreenshots();
    utils:log("\t[INFO] Screenshots cropped successfully.");
    utils:log("");

    // ── Phase 5 (cont.): Finalise ─────────────────────────────────────────────

    time:Utc endTime = time:utcNow();
    decimal durationSecs = time:utcDiffSeconds(endTime, startTime);

    // Aggregate direct API call costs
    int totalInputTokens  = promptGenUsage.inputTokens  + docEnfUsage.inputTokens;
    int totalOutputTokens = promptGenUsage.outputTokens + docEnfUsage.outputTokens;
    decimal totalCostUsd  = promptGenUsage.costUsd      + docEnfUsage.costUsd;

    // Add agent SDK cost to combined total
    decimal agentCostUsd = 0.0d;
    if agentCost is agent_client:AgentCost {
        decimal? ac = agentCost.totalCostUsd;
        if ac is decimal {
            agentCostUsd = ac;
        }
    }
    decimal totalCombinedCostUsd = totalCostUsd + agentCostUsd;

    // Step 17: Write run log to artifacts/run-log/
    utils:log("[STEP 17] Writing run log...");
    utils:writeRunLog({
        mode:                    triggerMode ? "trigger" : "connector",
        connectorName:           triggerMode ? () : targetName,
        connectorSlug:           triggerMode ? () : goalSlug,
        triggerName:             triggerMode ? targetName : (),
        triggerSlug:             triggerMode ? goalSlug : (),
        additionalInstructions:   additionalInstructions,
        startTime:           startTime,
        endTime:             endTime,
        durationSecs:        durationSecs,
        promptGenUsage:      promptGenUsage,
        docEnfUsage:         docEnfUsage,
        agentCost:           agentCost,
        totalDirectCostUsd:  totalCostUsd,
        totalCombinedCostUsd: totalCombinedCostUsd,
        promptPath:          promptPath,
        workflowDocPath:     enforcedDocPath == "" ? "(not written)" : enforcedDocPath
    });
    utils:log("");

    // Print pipeline stats
    utils:log("--- Pipeline Stats ---");
    utils:log(string `Start time:      ${time:utcToString(startTime)}`);
    utils:log(string `End time:        ${time:utcToString(endTime)}`);
    utils:log(string `Duration:        ${durationSecs}s`);
    utils:log(string `Prompt length:   ${fullPrompt.length()} chars`);
    utils:log("--- LLM Cost Breakdown ---");
    utils:log(string `Prompt gen:      ${promptGenUsage.inputTokens} in / ${promptGenUsage.outputTokens} out  |  $${promptGenUsage.costUsd}`);
    utils:log(string `Doc enforcement: ${docEnfUsage.inputTokens} in / ${docEnfUsage.outputTokens} out  |  $${docEnfUsage.costUsd}`);
    utils:log(string `Direct API total:${totalInputTokens} in / ${totalOutputTokens} out  |  $${totalCostUsd}`);
    utils:log(string `Agent SDK:       $${agentCostUsd}`);
    utils:log(string `COMBINED TOTAL:  $${totalCombinedCostUsd}`);

    utils:log("");
    utils:log("=== Pipeline Complete ===");
    utils:log("Artifacts saved under '" + utils:OUTPUT_DIR + "'.");
}
