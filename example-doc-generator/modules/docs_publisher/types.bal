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

# Options for publishing generated connector docs and samples.
public type PublishOptions record {|
    # Pipeline artifacts directory.
    string artifactsDir = "./artifacts";
    # Local docs-integrator fork path.
    string? docsRepo = ();
    # Fork slug, for example user/docs-integrator.
    string? forkSlug = ();
    # Upstream docs-integrator repo slug.
    string upstream = "wso2/docs-integrator";
    # Base branch used for the docs branch and PR.
    string baseBranch = "main";
    # Override connector catalog category.
    string? category = ();
    # Override publish branch name.
    string? branch = ();
    # Local integration-samples fork path.
    string? samplesRepo = ();
    # Fork slug, for example user/integration-samples.
    string? samplesForkSlug = ();
    # Upstream integration-samples repo slug.
    string samplesUpstream = "wso2/integration-samples";
    # Base branch used for the samples branch and PR.
    string samplesBaseBranch = "main";
    # Override sample publish branch name.
    string? samplesBranch = ();
    # Reuse an existing branch for batch publishing.
    boolean batchBranch = false;
    # Create a pull request after pushing.
    boolean createPr = false;
|};

# Result of a docs publish operation.
public type PublishResult record {|
    # Connector display name.
    string connectorName;
    # Connector slug.
    string connectorSlug;
    # Connector category.
    string category;
    # Branch pushed to origin.
    string branch;
    # Created pull request URL, when requested.
    string? prUrl = ();
    # True when no docs changes were committed.
    boolean noChanges = false;
|};

# Result of a sample publish operation.
public type SamplePublishResult record {|
    # Sample project name.
    string projectName;
    # Sample path under integration-samples.
    string samplePath;
    # Branch pushed to origin.
    string branch;
    # Created pull request URL, when requested.
    string? prUrl = ();
    # True when no sample changes were committed.
    boolean noChanges = false;
|};

# Result of publishing docs and samples for one connector.
public type PublishAllResult record {|
    # Documentation publish result.
    PublishResult docs;
    # Sample publish result.
    SamplePublishResult sample;
|};
