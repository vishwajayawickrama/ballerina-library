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

import ballerina/test;

@test:Config
function nestedCanvasAddStepProtocolTest() {
    string prompt = buildSystemPrompt("/tmp/example-doc-generator", "sap.businessone.projects", "sap_projects");
    string[] requiredInOrder = [
        "depth: 10",
        "boxes: true",
        "extension iframe",
        "resolved flow-canvas reference",
        "browser_evaluate",
        "svg[data-testid='empty-node-add-button-1']",
        "new MouseEvent(\"click\"",
        "bubbles: true",
        "view: element.ownerDocument.defaultView",
        "return true",
        "element.ownerDocument.elementFromPoint(x, y)",
        "empty-node-add-button-",
        "Immediately take a fresh deep",
        "Select the saved connection using its new reference",
        "Select the chosen operation using its refreshed reference"
    ];

    int searchFrom = 0;
    foreach string fragment in requiredInOrder {
        int? position = prompt.indexOf(fragment, searchFrom);
        test:assertTrue(position is int);
        searchFrom = <int>position + fragment.length();
    }

    test:assertTrue(!prompt.includes("Attempt `browser_click` **once**"));
    test:assertTrue(!prompt.includes("Hover **Start**"));
    test:assertTrue(prompt.includes("Coordinates are diagnostic only"));
    test:assertTrue(prompt.includes("Keep connection and operation names dynamic"));
}
