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

import wso2/example_doc_generator.image_processor;

# Crops generated screenshots and logs a compact summary.
#
# + options - crop options
# + return - an error if screenshot cropping fails
public function cropScreenshots(image_processor:ScreenshotCropOptions options = {}) returns error? {
    image_processor:ScreenshotCropSummary summary = check image_processor:cropScreenshots(options);
    foreach image_processor:ScreenshotCropFileResult result in summary.files {
        string baseName = re `^.*/`.replaceAll(result.path, "");
        if result.status == "processed" {
            if result.width is int && result.height is int && result.originalWidth is int && result.originalHeight is int {
                string label = result.message == "dry-run" ? "[DRY-RUN]" : "[CROP]";
                log("\t" + label + " " + baseName + ": " + result.originalWidth.toString() + "x"
                    + result.originalHeight.toString() + " -> " + result.width.toString()
                    + "x" + result.height.toString());
            }
        } else {
            log("\t[WARN] " + baseName + ": " + (result.message ?: "skipped"));
        }
    }
    if summary.files.length() == 0 {
        log("\t[INFO] No PNG screenshots found to crop.");
        return;
    }
    log("\t[INFO] Screenshot crop summary: processed=" + summary.processed.toString()
        + " skipped=" + summary.skipped.toString());
}
