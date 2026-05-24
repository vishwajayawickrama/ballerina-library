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

# Image dimensions and format metadata.
public type ImageInfo record {|
    # Image width in pixels.
    int width;
    # Image height in pixels.
    int height;
    # Image file format.
    string format;
|};

# Absolute pixel crop box.
public type CropBox record {|
    # Left x-coordinate.
    int x;
    # Top y-coordinate.
    int y;
    # Crop width.
    int width;
    # Crop height.
    int height;
|};

# Result of an image crop operation.
public type CropResult record {|
    # Source image path.
    string path;
    # Original width in pixels.
    int originalWidth;
    # Original height in pixels.
    int originalHeight;
    # Cropped width in pixels.
    int width;
    # Cropped height in pixels.
    int height;
    # Image file format.
    string format;
|};

# Pixel margins removed from each image.
public type CropMargins record {|
    # Pixels removed from the top edge.
    int top = 32;
    # Pixels removed from the bottom edge.
    int bottom = 18;
    # Pixels removed from the left edge.
    int left = 0;
    # Pixels removed from the right edge.
    int right = 0;
|};

# Options for directory-based screenshot crop operations.
public type ScreenshotCropOptions record {|
    # Directory containing PNG screenshots.
    string screenshotsDir = "artifacts/screenshots";
    # Margins to crop from each screenshot.
    CropMargins margins = {};
|};

# Per-file screenshot crop result.
public type ScreenshotCropFileResult record {|
    # Screenshot path.
    string path;
    # "processed" or "skipped".
    string status;
    # Optional detail for skipped entries.
    string? message = ();
    # Original image width.
    int? originalWidth = ();
    # Original image height.
    int? originalHeight = ();
    # Cropped image width.
    int? width = ();
    # Cropped image height.
    int? height = ();
|};

# Summary for a screenshot crop run.
public type ScreenshotCropSummary record {|
    # Number of processed screenshots.
    int processed = 0;
    # Number of skipped screenshots.
    int skipped = 0;
    # Total pixels before cropping.
    int totalPixelsBefore = 0;
    # Total pixels after cropping.
    int totalPixelsAfter = 0;
    # Per-file results.
    ScreenshotCropFileResult[] files = [];
|};

type ImageBridgeResponse record {|
    string 'type;
    string? message = ();
    ImageInfo? info = ();
    CropResult? result = ();
|};
