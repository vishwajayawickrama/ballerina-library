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

import ballerina/time;

type CentralPackageMetadata record {
    string readme?;
};

# Token usage and cost for a single direct LLM API call.
public type LlmCallUsage record {
    # Number of input tokens consumed.
    int inputTokens;
    # Number of output tokens generated.
    int outputTokens;
    # Estimated cost in USD.
    decimal costUsd;
};

# Token usage and cost reported by the Claude Agent SDK for the full agent run.
public type AgentRunCost record {
    # Total USD cost reported by the agent SDK.
    decimal? totalCostUsd;
    # Input tokens consumed across the entire agent run.
    int inputTokens;
    # Output tokens generated across the entire agent run.
    int outputTokens;
    # Cache read tokens.
    int cacheReadTokens;
    # Cache write tokens.
    int cacheWriteTokens;
    # Number of conversation turns in the agent run.
    int? numTurns;
};

# All data needed to write a pipeline run log entry.
public type RunLogEntry record {
    # The connector name.
    string connectorName;
    # Filename-safe slug derived from the connector name.
    string connectorSlug;
    # Optional extra instructions passed to the agent.
    string additionalInstructions;
    # Pipeline start time.
    time:Utc startTime;
    # Pipeline end time.
    time:Utc endTime;
    # Total pipeline duration in seconds.
    decimal durationSecs;
    # Token usage for the execution prompt generation call.
    LlmCallUsage promptGenUsage;
    # Token usage for the doc enforcement call.
    LlmCallUsage docEnfUsage;
    # Token usage and cost from the agent SDK run.
    AgentRunCost? agentCost;
    # Total cost of direct Anthropic API calls.
    decimal totalDirectCostUsd;
    # Combined cost including direct API calls and agent SDK.
    decimal totalCombinedCostUsd;
    # Path to the saved execution prompt file.
    string promptPath;
    # Path to the final workflow doc.
    string workflowDocPath;
};
