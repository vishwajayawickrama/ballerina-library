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
import ballerina/jballerina.java;

# Reads image metadata.
#
# + path - image path
# + return - image metadata, or an error
public function readInfo(string path) returns ImageInfo|error {
    string result = nativeReadInfo(path);
    json body = check result.fromJsonString();
    ImageBridgeResponse response = check body.cloneWithType(ImageBridgeResponse);
    if response.'type == "error" {
        return error(response.message ?: "Could not read image metadata");
    }
    ImageInfo? info = response.info;
    if info is ImageInfo {
        return info;
    }
    return error("Image metadata response did not include image info");
}

# Crops an image in place.
#
# + path - image path
# + cropBox - absolute pixel crop box
# + return - crop result, or an error
public function cropInPlace(string path, CropBox cropBox) returns CropResult|error {
    json cropJson = cropBox;
    string result = nativeCropInPlace(path, cropJson.toJsonString());
    json body = check result.fromJsonString();
    ImageBridgeResponse response = check body.cloneWithType(ImageBridgeResponse);
    if response.'type == "error" {
        return error(response.message ?: "Could not crop image");
    }
    CropResult? cropResult = response.result;
    if cropResult is CropResult {
        return cropResult;
    }
    return error("Crop response did not include crop result");
}

# Crops all PNG screenshots in the configured directory.
#
# + options - crop options
# + return - crop summary, or an error
public function cropScreenshots(ScreenshotCropOptions options = {}) returns ScreenshotCropSummary|error {
    ScreenshotCropSummary summary = {};
    file:MetaData|file:Error dirMeta = file:getMetaData(options.screenshotsDir);
    if dirMeta is file:Error || !dirMeta.dir {
        return summary;
    }

    file:MetaData[] entries = check file:readDir(options.screenshotsDir);
    foreach file:MetaData entry in entries {
        string path = entry.absPath;
        if !path.endsWith(".png") || path.endsWith(".orig.png") {
            continue;
        }
        ScreenshotCropFileResult result = check cropOne(path, options);
        if result.status == "processed" {
            summary.processed += 1;
            int? originalWidth = result.originalWidth;
            int? originalHeight = result.originalHeight;
            int? width = result.width;
            int? height = result.height;
            if originalWidth is int && originalHeight is int && width is int && height is int {
                summary.totalPixelsBefore += originalWidth * originalHeight;
                summary.totalPixelsAfter += width * height;
            }
        } else {
            summary.skipped += 1;
        }
        summary.files.push(result);
    }
    return summary;
}

function cropOne(string path, ScreenshotCropOptions options) returns ScreenshotCropFileResult|error {
    ImageInfo info = check readInfo(path);
    CropMargins margins = options.margins;
    int rightCoord = info.width - margins.right;
    int bottomCoord = info.height - margins.bottom;
    if margins.left < 0 || margins.top < 0 || margins.right < 0 || margins.bottom < 0 {
        return skipped(path, info, "margins must be non-negative");
    }
    if margins.left >= rightCoord || margins.top >= bottomCoord {
        return skipped(path, info, "margins exceed image size");
    }

    int newWidth = rightCoord - margins.left;
    int newHeight = bottomCoord - margins.top;
    CropResult cropResult = check cropInPlace(path, {
        x: margins.left,
        y: margins.top,
        width: newWidth,
        height: newHeight
    });
    return {
        path: path,
        status: "processed",
        originalWidth: cropResult.originalWidth,
        originalHeight: cropResult.originalHeight,
        width: cropResult.width,
        height: cropResult.height
    };
}

function skipped(string path, ImageInfo info, string message) returns ScreenshotCropFileResult {
    return {
        path: path,
        status: "skipped",
        message: message,
        originalWidth: info.width,
        originalHeight: info.height
    };
}

function nativeReadInfo(string path) returns string = @java:Method {
    'class: "org.wso2.exampledocgen.image.ImageKitBridge",
    name: "readInfo"
} external;

function nativeCropInPlace(string path, string cropBoxJson) returns string = @java:Method {
    'class: "org.wso2.exampledocgen.image.ImageKitBridge",
    name: "cropInPlace"
} external;
