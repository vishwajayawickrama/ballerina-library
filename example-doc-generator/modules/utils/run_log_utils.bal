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

import ballerina/io;
import ballerina/time;

const string RUN_LOG_DIR = "./artifacts/run-log";

# Writes a structured, pretty-printed JSON run log to artifacts/run-log/.
# Failures are logged as warnings — this function never propagates errors.
#
# + entry - all pipeline run metrics and artifact paths
public function writeRunLog(RunLogEntry entry) {
    io:Error? keepErr = io:fileWriteString(RUN_LOG_DIR + "/.keep", "");
    if keepErr is io:Error {
        log("\t[WARN] writeRunLog: could not create run-log dir: " + keepErr.message());
        return;
    }

    string timestamp = time:utcToString(entry.startTime);
    string tsSlug = re `[:\.]`.replaceAll(timestamp, "-");
    string logPath = RUN_LOG_DIR + "/" + entry.connectorSlug + "_" + tsSlug + ".json";

    AgentRunCost? ac = entry.agentCost;
    json agentCostJson = ac is AgentRunCost ? {
        "totalCostUsd":     ac.totalCostUsd,
        "inputTokens":      ac.inputTokens,
        "outputTokens":     ac.outputTokens,
        "cacheReadTokens":  ac.cacheReadTokens,
        "cacheWriteTokens": ac.cacheWriteTokens,
        "numTurns":         ac.numTurns
    } : "not available";

    json logJson = {
        "connectorName":            entry.connectorName,
        "connectorSlug":            entry.connectorSlug,
        "additionalInstructions":   entry.additionalInstructions == "" ? () : entry.additionalInstructions,
        "model":            "claude-sonnet-4-6",
        "startTime":        timestamp,
        "endTime":          time:utcToString(entry.endTime),
        "durationSeconds":  entry.durationSecs,
        "llmCalls": {
            "promptGeneration": {
                "inputTokens":  entry.promptGenUsage.inputTokens,
                "outputTokens": entry.promptGenUsage.outputTokens,
                "costUsd":      entry.promptGenUsage.costUsd
            },
            "docEnforcement": {
                "inputTokens":  entry.docEnfUsage.inputTokens,
                "outputTokens": entry.docEnfUsage.outputTokens,
                "costUsd":      entry.docEnfUsage.costUsd
            },
            "agentExecution": agentCostJson
        },
        "totalDirectApiCostUsd": entry.totalDirectCostUsd,
        "totalCombinedCostUsd":  entry.totalCombinedCostUsd,
        "artifacts": {
            "executionPromptPath": entry.promptPath,
            "workflowDocPath":     entry.workflowDocPath
        }
    };

    io:Error? writeErr = io:fileWriteJson(logPath, logJson);
    if writeErr is io:Error {
        log("\t[WARN] writeRunLog: could not write run log: " + writeErr.message());
    } else {
        log("\t[INFO] Run log saved to: " + logPath);
    }
}
