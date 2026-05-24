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

# Anthropic message content block.
type ContentBlock record {
    # The type of content block.
    string 'type;
    # The text content when type is "text".
    string text?;
};

# Anthropic token usage info.
type UsageInfo record {
    # Number of input tokens consumed.
    int input_tokens;
    # Number of output tokens generated.
    int output_tokens;
};

# Anthropic Messages API response fields used by this module.
type MessagesResponse record {
    # Unique identifier for this message.
    string id;
    # The model used to generate the response.
    string model;
    # The reason the model stopped generating.
    string stop_reason?;
    # The content blocks in the response.
    ContentBlock[] content;
    # Token usage for this response.
    UsageInfo? usage;
};

# Token usage and USD cost for a single LLM API call.
public type LlmUsage record {
    # Number of input tokens consumed.
    int inputTokens;
    # Number of output tokens generated.
    int outputTokens;
    # Estimated cost in USD.
    decimal costUsd;
};

# Result of a Claude API call.
public type LlmResult record {
    # The generated text content.
    string text;
    # Token usage and cost for this call.
    LlmUsage usage;
};
