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

import ballerina/jballerina.java;

# Opens a Claude Agent SDK session and starts receiving messages for the prompt.
#
# + config - SDK session configuration
# + prompt - user prompt to pass to Claude
# + return - an opaque session handle, or an error
public function openSession(AgentConfig config, string prompt) returns AgentSession|error {
    json configJson = config;
    return nativeOpenSession(configJson.toJsonString(), prompt);
}

# Reads the next normalized agent event from the session.
#
# + session - active SDK session
# + return - next event, a done event, or an error
public function nextEvent(AgentSession session) returns AgentEvent|error {
    string result = nativeNextEvent(session);
    AgentEvent event = check parseEvent(result);
    if event.'type == "error" {
        return error(event.text ?: "Claude Agent SDK returned an error");
    }
    return event;
}

# Closes the SDK session.
#
# + session - active SDK session
public function closeSession(AgentSession session) {
    nativeCloseSession(session);
}

function parseEvent(string eventJson) returns AgentEvent|error {
    json body = check eventJson.fromJsonString();
    return check body.cloneWithType(AgentEvent);
}

function nativeOpenSession(string configJson, string prompt) returns handle = @java:Method {
    'class: "org.wso2.exampledocgen.agent.ClaudeAgentBridge",
    name: "openSession"
} external;

function nativeNextEvent(handle session) returns string = @java:Method {
    'class: "org.wso2.exampledocgen.agent.ClaudeAgentBridge",
    name: "nextEvent"
} external;

function nativeCloseSession(handle session) = @java:Method {
    'class: "org.wso2.exampledocgen.agent.ClaudeAgentBridge",
    name: "closeSession"
} external;
