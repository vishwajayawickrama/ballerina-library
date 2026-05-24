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

const string DEFAULT_BATCH_BRANCH = "docs/connector-docs";
const string DEFAULT_SAMPLE_BATCH_BRANCH = "samples/connector-samples";

final map<string> categoryMap = {
    "mysql": "database", "postgresql": "database", "postgres": "database", "mongodb": "database",
    "mongo": "database", "mssql": "database", "sqlserver": "database", "redis": "database",
    "cassandra": "database", "oracle": "database", "oracledb": "database", "sqlite": "database",
    "h2": "database", "snowflake": "database", "java.jdbc": "database", "jdbc": "database",
    "cdc": "database", "aws.redshift": "database", "redshift": "database", "aws.redshiftdata": "database",
    "kafka": "messaging", "rabbitmq": "messaging", "nats": "messaging", "activemq": "messaging",
    "ibmmq": "messaging", "ibm.ibmmq": "messaging", "asb": "messaging", "aws.sqs": "messaging",
    "sqs": "messaging", "gcloud.pubsub": "messaging", "pubsub": "messaging", "java.jms": "messaging",
    "jms": "messaging", "solace": "messaging", "salesforce": "crm-sales", "hubspot": "crm-sales",
    "zoho": "crm-sales", "pipedrive": "crm-sales", "dynamics": "crm-sales", "slack": "communication",
    "teams": "communication", "gmail": "communication", "googleapis.gmail": "communication",
    "outlook": "communication", "twilio": "communication", "sendgrid": "communication",
    "discord": "communication", "zoom": "communication", "zoom.meetings": "communication",
    "zoom.scheduler": "communication", "aws.sns": "communication", "sns": "communication",
    "gcs": "cloud-infrastructure", "azure": "cloud-infrastructure", "aws.lambda": "cloud-infrastructure",
    "lambda": "cloud-infrastructure", "azure.functions": "cloud-infrastructure", "elastic": "cloud-infrastructure",
    "elastic.elasticcloud": "cloud-infrastructure", "openai": "ai-ml", "ai.openai": "ai-ml",
    "anthropic": "ai-ml", "ai.anthropic": "ai-ml", "cohere": "ai-ml", "gemini": "ai-ml",
    "mistral": "ai-ml", "ai.azure": "ai-ml", "ai.ollama": "ai-ml", "ollama": "ai-ml",
    "ai.deepseek": "ai-ml", "deepseek": "ai-ml", "ai.pinecone": "ai-ml", "pinecone": "ai-ml",
    "ai.weaviate": "ai-ml", "weaviate": "ai-ml", "ai.devant": "ai-ml", "ai.memory.mssql": "ai-ml",
    "azure.ai.search": "ai-ml", "shopify": "ecommerce", "woocommerce": "ecommerce",
    "stripe": "finance-accounting", "paypal": "finance-accounting", "github": "developer-tools",
    "gitlab": "developer-tools", "confluence": "developer-tools", "bitbucket": "developer-tools",
    "jira": "productivity-collaboration", "asana": "productivity-collaboration",
    "trello": "productivity-collaboration", "googledrive": "productivity-collaboration",
    "microsoft.onedrive": "productivity-collaboration", "googleapis.sheets": "productivity-collaboration",
    "googleapis.calendar": "productivity-collaboration", "googleapis.gcalendar": "productivity-collaboration",
    "smartsheet": "productivity-collaboration", "candid": "productivity-collaboration",
    "s3": "storage-file", "awss3": "storage-file", "aws.s3": "storage-file",
    "onedrive": "storage-file", "alfresco": "storage-file", "azure_storage_service": "storage-file",
    "sap": "erp-business", "netsuite": "erp-business", "workday": "hrms",
    "aws.secretmanager": "security-identity", "secretmanager": "security-identity",
    "aws.secretsmanager": "security-identity", "secretsmanager": "security-identity",
    "scim": "security-identity", "scim2": "security-identity", "hrms": "hrms",
    "sftp": "connectivity", "smtp": "connectivity", "imap": "connectivity",
    "email": "built-in", "ftp": "built-in", "graphql": "built-in", "grpc": "built-in",
    "http": "built-in", "mqtt": "built-in", "tcp": "built-in", "udp": "built-in",
    "websocket": "built-in", "websub": "built-in", "hubspot.marketing.campaigns": "marketing-social",
    "hubspot.marketing.emails": "marketing-social", "hubspot.marketing.events": "marketing-social",
    "hubspot.marketing.forms": "marketing-social", "hubspot.marketing.subscriptions": "marketing-social",
    "hubspot.marketing.transactional": "marketing-social", "mailchimp.marketing": "marketing-social",
    "mailchimp.transactional": "marketing-social", "salesforce.marketingcloud": "marketing-social",
    "twitter": "marketing-social"
};

# Publishes connector docs from the current artifacts directory.
#
# + createPr - create a pull request after pushing
# + return - publish result, or an error
public function publishCurrentRun(boolean createPr = false) returns PublishAllResult|error {
    return publishDocsAndSamples({createPr});
}

# Creates a pull request for an existing docs batch branch.
#
# + branch - batch branch name
# + options - publish options
# + return - created pull request URL, or an error
public function createBatchPullRequest(string branch = DEFAULT_BATCH_BRANCH, PublishOptions options = {}) returns string|error {
    string docsRepo = check resolveDocsRepo(options.docsRepo);
    check validateDocsRepo(docsRepo);
    string forkSlug = check resolveFork(docsRepo, options.forkSlug);
    return check createGitHubPullRequest(docsRepo, forkSlug, options.upstream, options.baseBranch, branch,
        "docs: adding docs from " + branch, buildBatchPrBody(branch));
}

# Creates a pull request for an existing integration-samples batch branch.
#
# + branch - batch branch name
# + options - publish options
# + return - created pull request URL, or an error
public function createBatchSamplePullRequest(string branch = DEFAULT_SAMPLE_BATCH_BRANCH,
        PublishOptions options = {}) returns string|error {
    string samplesRepo = check resolveSamplesRepo(options.samplesRepo);
    check validateSamplesRepo(samplesRepo);
    string forkSlug = check resolveFork(samplesRepo, options.samplesForkSlug);
    return check createGitHubPullRequest(samplesRepo, forkSlug, options.samplesUpstream, options.samplesBaseBranch,
        branch, "samples: adding samples from " + branch, buildBatchSamplePrBody(branch));
}

# Publishes connector docs and integration sample from the given artifacts directory.
#
# + options - publish options
# + return - combined publish result, or an error
public function publishDocsAndSamples(PublishOptions options = {}) returns PublishAllResult|error {
    PublishResult docs = check publishDocs(options);
    SamplePublishResult sample = check publishSample(options);
    return {docs, sample};
}

# Publishes connector docs from the given artifacts directory.
#
# + options - publish options
# + return - publish result, or an error
public function publishDocs(PublishOptions options = {}) returns PublishResult|error {
    string artifactsDir = options.artifactsDir;
    string docsRepo = check resolveDocsRepo(options.docsRepo);
    check validateDocsRepo(docsRepo);

    string connectorName = check readConnectorName(artifactsDir);
    string connectorSlug = slugify(connectorName);
    string category = check detectCategory(connectorSlug, options.category);
    string branch = options.branch ?: (options.batchBranch ? DEFAULT_BATCH_BRANCH :
        "docs/add-" + connectorSlug + "-connector-example-documentation");
    string forkSlug = check resolveFork(docsRepo, options.forkSlug);

    if options.batchBranch {
        check checkoutOrCreateBatchBranch(docsRepo, branch, options.upstream, options.baseBranch);
    } else {
        check syncAndCreateBranch(docsRepo, branch, options.upstream, options.baseBranch);
    }

    string sourceDoc = check latestWorkflowDoc(artifactsDir);
    string examplePath = docsRepo + "/en/docs/connectors/catalog/" + category + "/" + connectorSlug + "/example.md";
    string screenshotDir = docsRepo + "/en/static/img/connectors/catalog/" + category + "/" + connectorSlug;
    string sidebarPath = docsRepo + "/en/sidebars.ts";

    check placeDoc(sourceDoc, examplePath, "/img/connectors/catalog/" + category + "/" + connectorSlug + "/");
    check copyScreenshots(artifactsDir, screenshotDir);
    check updateSidebar(sidebarPath, category, connectorSlug);

    boolean noChanges = check commitAndPush(docsRepo, branch, [
        examplePath,
        screenshotDir,
        sidebarPath
    ], "docs: add " + connectorName + " connector example guide");

    string? prUrl = ();
    if options.createPr {
        prUrl = check createDocsPullRequest(docsRepo, forkSlug, options.upstream, options.baseBranch, branch,
            connectorName, connectorSlug, category, options.batchBranch);
    }

    return {
        connectorName,
        connectorSlug,
        category,
        branch,
        prUrl,
        noChanges
    };
}

# Publishes the generated connector integration sample.
#
# + options - publish options
# + return - sample publish result, or an error
public function publishSample(PublishOptions options = {}) returns SamplePublishResult|error {
    string artifactsDir = options.artifactsDir;
    string samplesRepo = check resolveSamplesRepo(options.samplesRepo);
    check validateSamplesRepo(samplesRepo);

    string sampleProject = check resolveCreatedProject(artifactsDir);
    string projectName = baseName(sampleProject);
    string branch = options.samplesBranch ?: (options.batchBranch ? DEFAULT_SAMPLE_BATCH_BRANCH :
        "samples/add-" + slugify(projectName) + "-connector-sample");
    string forkSlug = check resolveFork(samplesRepo, options.samplesForkSlug);

    if options.batchBranch {
        check checkoutOrCreateBatchBranch(samplesRepo, branch, options.samplesUpstream, options.samplesBaseBranch);
    } else {
        check syncAndCreateBranch(samplesRepo, branch, options.samplesUpstream, options.samplesBaseBranch);
    }

    check normalizeSampleOrg(sampleProject);

    string samplePath = "connectors/" + projectName;
    string sampleDest = samplesRepo + "/" + samplePath;
    check removePath(sampleDest);
    check copyDir(sampleProject, sampleDest);

    string logDir = artifactsDir + "/run-log";
    check file:createDir(logDir, file:RECURSIVE);
    check io:fileWriteString(logDir + "/published-sample-path.txt", samplePath);

    boolean noChanges = check commitAndPush(samplesRepo, branch, [sampleDest],
        "samples: add " + projectName + " connector integration sample");

    string? prUrl = ();
    if options.createPr {
        prUrl = check createGitHubPullRequest(samplesRepo, forkSlug, options.samplesUpstream,
            options.samplesBaseBranch, branch,
            options.batchBranch ? "samples: adding samples from " + branch :
                "samples: add " + projectName + " connector integration sample",
            options.batchBranch ? buildBatchSamplePrBody(branch) : buildSamplePrBody(projectName, samplePath));
    }

    return {
        projectName,
        samplePath,
        branch,
        prUrl,
        noChanges
    };
}

function resolveDocsRepo(string? explicitRepo) returns string|error {
    if explicitRepo is string && explicitRepo.trim() != "" {
        return explicitRepo.trim();
    }
    string cwd = file:getCurrentDir();
    return cwd + "/../../docs-integrator";
}

function resolveSamplesRepo(string? explicitRepo) returns string|error {
    if explicitRepo is string && explicitRepo.trim() != "" {
        return explicitRepo.trim();
    }
    string cwd = file:getCurrentDir();
    return cwd + "/../../integration-samples";
}

function validateDocsRepo(string docsRepo) returns error? {
    if !(check exists(docsRepo + "/.git")) {
        return error(docsRepo + " is not a git repository.");
    }
    if !(check exists(docsRepo + "/en")) {
        return error(docsRepo + "/en not found. Ensure this is docs-integrator.");
    }
}

function validateSamplesRepo(string samplesRepo) returns error? {
    if !(check exists(samplesRepo + "/.git")) {
        return error(samplesRepo + " is not a git repository.");
    }
}

function readConnectorName(string artifactsDir) returns string|error {
    string|io:Error content = io:fileReadString(artifactsDir + "/run-log/connector-name.txt");
    if content is io:Error {
        return error("connector-name.txt not found under " + artifactsDir + "/run-log.");
    }
    string name = content.trim();
    if name == "" {
        return error("connector-name.txt is empty.");
    }
    return name;
}

function latestWorkflowDoc(string artifactsDir) returns string|error {
    string docsDir = artifactsDir + "/workflow-docs";
    file:MetaData[] entries = check file:readDir(docsDir);
    file:MetaData? latest = ();
    foreach file:MetaData entry in entries {
        if entry.absPath.endsWith(".md") {
            if latest is () || time:utcDiffSeconds(entry.modifiedTime, latest.modifiedTime) > 0d {
                latest = entry;
            }
        }
    }
    if latest is file:MetaData {
        return latest.absPath;
    }
    return error("No workflow doc found under " + docsDir + ".");
}

function placeDoc(string sourceDoc, string examplePath, string staticImgPrefix) returns error? {
    string content = check io:fileReadString(sourceDoc);
    string updated = re `\.\./screenshots/`.replaceAll(content, staticImgPrefix);
    check file:createDir(parentDir(examplePath), file:RECURSIVE);
    check io:fileWriteString(examplePath, updated);
}

function copyScreenshots(string artifactsDir, string screenshotDir) returns error? {
    string sourceDir = artifactsDir + "/screenshots";
    if !(check exists(sourceDir)) {
        return;
    }
    check file:createDir(screenshotDir, file:RECURSIVE);
    file:MetaData[] entries = check file:readDir(sourceDir);
    foreach file:MetaData entry in entries {
        string path = entry.absPath;
        if path.endsWith(".png") && !path.endsWith(".orig.png") {
            byte[] content = check io:fileReadBytes(path);
            check io:fileWriteBytes(screenshotDir + "/" + baseName(path), content);
        }
    }
}

function resolveCreatedProject(string artifactsDir) returns string|error {
    string|io:Error content = io:fileReadString(artifactsDir + "/run-log/created-project.txt");
    if content is io:Error {
        return error("created-project.txt not found under " + artifactsDir + "/run-log.");
    }
    string path = content.trim();
    if path == "" {
        return error("created-project.txt is empty.");
    }
    if check exists(path + "/Ballerina.toml") {
        return path;
    }
    file:MetaData[] entries = check file:readDir(path);
    foreach file:MetaData entry in entries {
        if entry.dir && (check exists(entry.absPath + "/Ballerina.toml")) {
            return entry.absPath;
        }
    }
    return error("Could not find a Ballerina sample project under " + path + ".");
}

function normalizeSampleOrg(string sampleProject) returns error? {
    string tomlPath = sampleProject + "/Ballerina.toml";
    string content = check io:fileReadString(tomlPath);
    string[] lines = re `\n`.split(content);
    foreach int i in 0 ..< lines.length() {
        if lines[i].trim().startsWith("org") && lines[i].includes("=") {
            lines[i] = "org = \"wso2\"";
            break;
        }
    }
    string updated = joinStrings(lines, "\n");
    check io:fileWriteString(tomlPath, updated);
}

function copyDir(string sourceDir, string destDir) returns error? {
    check file:createDir(destDir, file:RECURSIVE);
    file:MetaData[] entries = check file:readDir(sourceDir);
    foreach file:MetaData entry in entries {
        string name = baseName(entry.absPath);
        if name == ".git" {
            continue;
        }
        string destPath = destDir + "/" + name;
        if entry.dir {
            check copyDir(entry.absPath, destPath);
        } else {
            byte[] content = check io:fileReadBytes(entry.absPath);
            check io:fileWriteBytes(destPath, content);
        }
    }
}

function removePath(string path) returns error? {
    if !(check exists(path)) {
        return;
    }
    check runCommand("rm", ["-rf", path], ".");
}

function updateSidebar(string sidebarPath, string category, string connectorSlug) returns error? {
    string content = check io:fileReadString(sidebarPath);
    string exampleId = "connectors/catalog/" + category + "/" + connectorSlug + "/example";
    if content.includes(exampleId) {
        return;
    }
    string overviewId = "connectors/catalog/" + category + "/" + connectorSlug + "/overview";
    int? overviewIndex = content.indexOf(overviewId);
    if overviewIndex is () {
        return error("Could not find sidebar overview entry for " + connectorSlug + ".");
    }
    int? itemsIndex = indexOfFrom(content, "items:", overviewIndex);
    if itemsIndex is () {
        return error("Could not find sidebar items array for " + connectorSlug + ".");
    }
    int? openBracket = indexOfFrom(content, "[", itemsIndex);
    if openBracket is () {
        return error("Could not find sidebar items array opening bracket for " + connectorSlug + ".");
    }
    int closeBracket = check findMatchingBracket(content, openBracket);
    string insert = "\n          '" + exampleId + "',";
    string updated = content.substring(0, closeBracket) + insert + content.substring(closeBracket);
    check io:fileWriteString(sidebarPath, updated);
}

function syncAndCreateBranch(string docsRepo, string branch, string upstream, string baseBranch) returns error? {
    check ensureUpstreamRemote(docsRepo, upstream);
    check runCommand("git", ["fetch", "upstream"], docsRepo);
    check runCommand("git", ["checkout", baseBranch], docsRepo);
    check runCommand("git", ["merge", "upstream/" + baseBranch, "--ff-only"], docsRepo);
    check runCommand("git", ["checkout", "-B", branch], docsRepo);
}

function checkoutOrCreateBatchBranch(string docsRepo, string branch, string upstream, string baseBranch) returns error? {
    check ensureUpstreamRemote(docsRepo, upstream);
    check runCommand("git", ["fetch", "origin"], docsRepo);
    check runCommand("git", ["fetch", "upstream"], docsRepo);
    if branchExistsOnOrigin(docsRepo, branch) {
        check runCommand("git", ["checkout", "-B", branch, "origin/" + branch], docsRepo);
    } else {
        check runCommand("git", ["checkout", baseBranch], docsRepo);
        check runCommand("git", ["merge", "upstream/" + baseBranch, "--ff-only"], docsRepo);
        check runCommand("git", ["checkout", "-B", branch], docsRepo);
    }
    check runCommand("git", ["merge", "upstream/" + baseBranch, "--no-edit"], docsRepo);
}

function ensureUpstreamRemote(string docsRepo, string upstream) returns error? {
    string remotes = check commandOutput("git", ["remote"], docsRepo);
    foreach string remoteName in re `\n`.split(remotes) {
        if remoteName.trim() == "upstream" {
            return;
        }
    }
    return error("'upstream' remote not found. Add it with: git remote add upstream https://github.com/" + upstream + ".git");
}

function branchExistsOnOrigin(string docsRepo, string branch) returns boolean {
    os:Process|error proc = os:exec({
        value: "sh",
        arguments: ["-c", "cd " + shellQuote(docsRepo) + " && git ls-remote --heads origin " + shellQuote(branch)]
    });
    if proc is error {
        return false;
    }
    byte[]|error outBytes = proc.output();
    int|error exitCode = proc.waitForExit();
    if exitCode is int && exitCode == 0 && outBytes is byte[] {
        string|error output = string:fromBytes(outBytes);
        return output is string && output.trim() != "";
    }
    return false;
}

function commitAndPush(string repo, string branch, string[] generatedPaths, string message) returns boolean|error {
    string[] addArgs = ["add", "--"];
    foreach string path in generatedPaths {
        addArgs.push(path);
    }
    check runCommand("git", addArgs, repo);
    string status = check commandOutput("git", ["diff", "--cached", "--name-only"], repo);
    if status.trim() == "" {
        check runCommand("git", ["push", "origin", branch], repo);
        return true;
    }
    check runCommand("git", ["commit", "-m", message], repo);
    check runCommand("git", ["push", "origin", branch], repo);
    return false;
}

function createDocsPullRequest(string docsRepo, string forkSlug, string upstream, string baseBranch, string branch,
        string connectorName, string connectorSlug, string category, boolean batchBranch) returns string|error {
    string title = batchBranch ? "docs: adding docs from " + branch :
        "docs: add " + connectorName + " connector example guide";
    string body = batchBranch ? buildBatchPrBody(branch) :
        buildPrBody(connectorName, connectorSlug, category);
    return check createGitHubPullRequest(docsRepo, forkSlug, upstream, baseBranch, branch, title, body);
}

function createGitHubPullRequest(string repo, string forkSlug, string upstream, string baseBranch, string branch,
        string title, string body) returns string|error {
    string forkOwner = re `/.*$`.replaceAll(forkSlug, "");
    string head = forkOwner + ":" + branch;
    return check commandOutput("gh", [
        "pr", "create",
        "--repo", upstream,
        "--head", head,
        "--base", baseBranch,
        "--title", title,
        "--body", body
    ], repo);
}

function buildPrBody(string connectorName, string connectorSlug, string category) returns string {
    return "## Purpose\n\n" +
        "Adds a step-by-step example guide for the " + connectorName + " connector with embedded screenshots.\n\n" +
        "## Goals\n\n" +
        "- Provide a complete walkthrough for configuring the connector in the WSO2 Integrator low-code canvas\n" +
        "- Include screenshots at each key configuration step\n\n" +
        "## Documentation\n\n" +
        "- `en/docs/connectors/catalog/" + category + "/" + connectorSlug + "/example.md`\n" +
        "- `en/static/img/connectors/catalog/" + category + "/" + connectorSlug + "/`\n" +
        "- `en/sidebars.ts`\n\n" +
        "## Security checks\n\n" +
        "- Followed secure coding standards: N/A (documentation only)\n" +
        "- Ran FindSecurityBugs plugin: N/A (documentation only)\n";
}

function buildBatchPrBody(string branch) returns string {
    return "## Purpose\n\n" +
        "Adds generated connector example guides committed through the documentation pipeline.\n\n" +
        "## Goals\n\n" +
        "- Provide low-code canvas walkthroughs for the included connectors\n" +
        "- Include screenshots at each key configuration step\n\n" +
        "## Approach\n\n" +
        "Content generated by the connector docs automation pipeline and committed to branch `" + branch + "`.\n\n" +
        "## Security checks\n\n" +
        "- Followed secure coding standards: N/A (documentation only)\n" +
        "- Ran FindSecurityBugs plugin: N/A (documentation only)\n";
}

function buildSamplePrBody(string projectName, string samplePath) returns string {
    return "## Purpose\n\n" +
        "Adds the generated integration sample for the " + projectName + " connector.\n\n" +
        "## Sample\n\n" +
        "- `" + samplePath + "`\n\n" +
        "## Security checks\n\n" +
        "- Followed secure coding standards: Yes\n" +
        "- Ran FindSecurityBugs plugin: N/A\n";
}

function buildBatchSamplePrBody(string branch) returns string {
    return "## Purpose\n\n" +
        "Adds generated connector integration samples committed through the documentation pipeline.\n\n" +
        "## Approach\n\n" +
        "Samples generated by the connector docs automation pipeline and committed to branch `" + branch + "`.\n\n" +
        "## Security checks\n\n" +
        "- Followed secure coding standards: Yes\n" +
        "- Ran FindSecurityBugs plugin: N/A\n";
}

function resolveFork(string docsRepo, string? explicitFork) returns string|error {
    if explicitFork is string && explicitFork.trim() != "" {
        return explicitFork.trim();
    }
    string remoteUrl = check commandOutput("git", ["remote", "get-url", "origin"], docsRepo);
    string cleaned = remoteUrl.trim().endsWith(".git") ? remoteUrl.trim().substring(0, remoteUrl.trim().length() - 4) : remoteUrl.trim();
    int? slash = cleaned.lastIndexOf("/");
    if slash is int {
        string repo = cleaned.substring(slash + 1);
        string prefix = cleaned.substring(0, slash);
        int? ownerSlash = prefix.lastIndexOf("/");
        int? ownerColon = prefix.lastIndexOf(":");
        int ownerStart = 0;
        if ownerSlash is int {
            ownerStart = ownerSlash + 1;
        } else if ownerColon is int {
            ownerStart = ownerColon + 1;
        }
        return prefix.substring(ownerStart) + "/" + repo;
    }
    return error("Could not infer fork from origin remote.");
}

function detectCategory(string connectorSlug, string? explicitCategory) returns string|error {
    if explicitCategory is string && explicitCategory.trim() != "" {
        return explicitCategory.trim().toLowerAscii();
    }
    string? exact = categoryMap[connectorSlug];
    if exact is string {
        return exact;
    }
    foreach [string, string] [key, category] in categoryMap.entries() {
        if connectorSlug.includes(key) || key.includes(connectorSlug) {
            return category;
        }
    }
    return error("Could not auto-detect category for connector '" + connectorSlug + "'. Pass category=<category>.");
}

function slugify(string name) returns string {
    string slug = name.trim().toLowerAscii();
    slug = re `\s+`.replaceAll(slug, "-");
    slug = re `[^a-z0-9.]+`.replaceAll(slug, "-");
    return re `(^[-.]+|[-.]+$)`.replaceAll(slug, "");
}

function runCommand(string value, string[] arguments, string workingDir) returns error? {
    _ = check commandOutput(value, arguments, workingDir);
}

function commandOutput(string value, string[] arguments, string workingDir) returns string|error {
    string command = "cd " + shellQuote(workingDir) + " && " + shellQuote(value);
    foreach string argument in arguments {
        command += " " + shellQuote(argument);
    }
    os:Process|error proc = os:exec({
        value: "sh",
        arguments: ["-c", command]
    });
    if proc is error {
        return error("Failed to launch `" + value + "`: " + proc.message());
    }
    byte[]|error outBytes = proc.output();
    int|error exitCode = proc.waitForExit();
    if exitCode is error {
        return error("Command `" + value + "` failed: " + exitCode.message());
    }
    if exitCode != 0 {
        return error("Command `" + value + " " + joinStrings(arguments, " ") + "` failed with exit code " + exitCode.toString());
    }
    if outBytes is error {
        return error("Could not read output from `" + value + "`: " + outBytes.message());
    }
    string|error output = string:fromBytes(outBytes);
    if output is error {
        return error("Could not decode output from `" + value + "`: " + output.message());
    }
    return output.trim();
}

function exists(string path) returns boolean|error {
    boolean|file:Error result = file:test(path, file:EXISTS);
    if result is file:Error {
        return error("Could not check path " + path + ": " + result.message());
    }
    return result;
}

function parentDir(string path) returns string {
    int? index = path.lastIndexOf("/");
    return index is int ? path.substring(0, index) : ".";
}

function baseName(string path) returns string {
    int? index = path.lastIndexOf("/");
    return index is int ? path.substring(index + 1) : path;
}

function indexOfFrom(string value, string needle, int startIndex) returns int? {
    int? index = value.substring(startIndex).indexOf(needle);
    return index is int ? startIndex + index : ();
}

function findMatchingBracket(string value, int openIndex) returns int|error {
    int depth = 0;
    foreach int i in openIndex ..< value.length() {
        string char = value.substring(i, i + 1);
        if char == "[" {
            depth += 1;
        } else if char == "]" {
            depth -= 1;
            if depth == 0 {
                return i;
            }
        }
    }
    return error("Could not find matching closing bracket.");
}

function joinStrings(string[] values, string separator) returns string {
    string result = "";
    foreach int i in 0 ..< values.length() {
        if i > 0 {
            result += separator;
        }
        result += values[i];
    }
    return result;
}

function shellQuote(string value) returns string {
    return "'" + re `'`.replaceAll(value, "'\"'\"'") + "'";
}
