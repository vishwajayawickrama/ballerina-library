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

import ballerina/lang.runtime;
import ballerina/jballerina.java;
import wso2/example_doc_generator.utils;

# Structured cost data returned by the agent bridge once the job completes.
public type AgentCost record {
    # Total USD cost reported by the Claude Agent SDK (nil if not available)
    decimal? totalCostUsd;
    # Input tokens consumed across the entire agent run
    int inputTokens;
    # Output tokens generated across the entire agent run
    int outputTokens;
    # Cache read tokens (prompt caching)
    int cacheReadTokens;
    # Cache write tokens (prompt caching)
    int cacheWriteTokens;
    # Number of conversation turns in the agent run (nil if not available)
    int? numTurns;
};

# Poll response for a running or completed in-process agent job.
type JobStatus record {
    # "queued", "running", "done", or "error"
    string status;
    # Accumulated log lines in "[LABEL] text" format
    string[] logs;
    # Structured cost data — present only after the job completes
    AgentCost? cost;
};

# Initializes the Java Claude agent bridge.
#
# + return - an error if the Java bridge could not be loaded
public function initAgentBridge() returns error? {
    string result = javaBridgeInit();
    if result != "ok" {
        return error("Java agent bridge returned unexpected init result: " + result);
    }
}

# Submits the execution prompt to the Java agent bridge and streams its log
# lines to the console as they arrive, blocking until the job is marked done.
#
# + promptPath - absolute or relative path to the generated execution prompt file
# + return     - AgentCost if available, nil if cost data was absent, or an error
public function runClaudeAgent(string promptPath) returns AgentCost?|error {
    string jobId = javaBridgeStartRun(promptPath);
    utils:log("\t[INFO] Job submitted: " + jobId);

    // Poll every second; print new log lines as they arrive
    // Limit to 5400 attempts (90 minutes) to prevent infinite hangs.
    int lastLogCount = 0;
    int attempts = 0;
    int maxAttempts = 5400;
    while attempts < maxAttempts {
        runtime:sleep(1);
        attempts += 1;
        string jobJson = javaBridgeGetJob(jobId);
        json pollBody = check jobJson.fromJsonString();
        JobStatus jobStatus = check pollBody.cloneWithType(JobStatus);

        int i = lastLogCount;
        while i < jobStatus.logs.length() {
            utils:log("\t" + jobStatus.logs[i]);
            i += 1;
        }
        lastLogCount = jobStatus.logs.length();

        if jobStatus.status == "done" {
            utils:log("\t[INFO] Claude agent finished.");
            return jobStatus.cost;
        }
        if jobStatus.status == "error" {
            return error(string `Agent job ${jobId} failed. Check agent logs for details.`);
        }
    }
    return error(string `Agent job ${jobId} did not complete within ${maxAttempts} seconds.`);
}

# Requests the Java agent bridge to cancel active jobs and release executor resources.
# This is a best-effort cleanup step; callers can log the returned error without
# failing the completed pipeline.
#
# + return - an error if the shutdown request could not be completed
public function stopAgentBridge() returns error? {
    javaBridgeShutdown();
}

function javaBridgeInit() returns string = @java:Method {
    'class: "org.wso2.exampledocgen.agent.ClaudeAgentBridge",
    name: "init"
} external;

function javaBridgeStartRun(string promptPath) returns string = @java:Method {
    'class: "org.wso2.exampledocgen.agent.ClaudeAgentBridge",
    name: "startRun"
} external;

function javaBridgeGetJob(string jobId) returns string = @java:Method {
    'class: "org.wso2.exampledocgen.agent.ClaudeAgentBridge",
    name: "getJob"
} external;

function javaBridgeShutdown() = @java:Method {
    'class: "org.wso2.exampledocgen.agent.ClaudeAgentBridge",
    name: "shutdown"
} external;
