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
import tensors/imagekit;

const string SCREENSHOTS_DIR = "./artifacts/screenshots";

# Crops UI chrome from pipeline screenshots in-place.
#
# + dryRun - print planned crop operations without writing files
# + backup - write .orig.png backups before replacing images
# + return - an error if cropping fails
public function cropScreenshots(boolean dryRun = false, boolean backup = false) returns error? {
    return cropScreenshotsWithMargins(
        dryRun,
        backup,
        top = 32,
        bottom = 18,
        left = 0,
        right = 0
    );
}

# Crops UI chrome from pipeline screenshots in-place with explicit margins.
#
# + dryRun - print planned crop operations without writing files
# + backup - write .orig.png backups before replacing images
# + top - pixels to crop from the top edge
# + bottom - pixels to crop from the bottom edge
# + left - pixels to crop from the left edge
# + right - pixels to crop from the right edge
# + return - an error if cropping fails
public function cropScreenshotsWithMargins(
    boolean dryRun = false,
    boolean backup = false,
    int top = 32,
    int bottom = 18,
    int left = 0,
    int right = 0
) returns error? {
    boolean screenshotsDirExists = check file:test(SCREENSHOTS_DIR, file:EXISTS);
    if !screenshotsDirExists {
        log("[INFO] " + SCREENSHOTS_DIR + " does not exist — no screenshots to crop.");
        return;
    }

    check removeDebugScreenshots();
    check validateCropMargin("cropTop", top);
    check validateCropMargin("cropBottom", bottom);
    check validateCropMargin("cropLeft", left);
    check validateCropMargin("cropRight", right);

    imagekit:CropSummary summary = check imagekit:cropDirectory(
        SCREENSHOTS_DIR,
        top = top,
        bottom = bottom,
        left = left,
        right = right,
        dryRun = dryRun,
        backup = backup
    );

    log("");
    log("── Crop Summary ──────────────────────────────────");
    log("  Files processed : " + summary.processed.toString());
    log("  Files skipped   : " + summary.skipped.toString());
    log("  Pixel reduction : ~" + summary.pixelReductionPct.toString() + "%");
    if dryRun {
        log("  (dry-run — no files were written)");
    }
    log("──────────────────────────────────────────────────");
}

function removeDebugScreenshots() returns error? {
    file:MetaData[] entries = check file:readDir(SCREENSHOTS_DIR);
    foreach file:MetaData entry in entries {
        if entry.absPath.endsWith(".png") && fileName(entry.absPath).startsWith("debug-") {
            file:Error? removeErr = file:remove(entry.absPath);
            if removeErr is file:Error {
                log("\t[WARN] Could not remove leaked debug screenshot " + fileName(entry.absPath) +
                    ": " + removeErr.message());
            } else {
                log("[INFO] Removed leaked debug screenshot: " + fileName(entry.absPath));
            }
        }
    }
}

function validateCropMargin(string name, int margin) returns error? {
    if margin < 0 {
        return error("Config.toml value " + name + " must be >= 0, got: " + margin.toString());
    }
}

function fileName(string path) returns string {
    string[] parts = re`/`.split(path);
    return parts.length() == 0 ? path : parts[parts.length() - 1];
}
