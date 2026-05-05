// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ballerina/os;

public const string ANTHROPIC_API_KEY_ENV = "ANTHROPIC_API_KEY";

# Exports the configured Anthropic API key into this process environment when a
# caller explicitly wants child processes to inherit ANTHROPIC_API_KEY.
#
# + apiKey - the Anthropic API key read from Ballerina configuration
# + return - an error if the key is empty or cannot be exported
public function exportAnthropicApiKeyForChildProcesses(string apiKey) returns error? {
    string trimmed = apiKey.trim();
    if trimmed == "" {
        return error("anthropicApiKey is empty. Set it in Config.toml.");
    }
    check os:setEnv(ANTHROPIC_API_KEY_ENV, trimmed);
}
