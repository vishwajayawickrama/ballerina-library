// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.bal run -- snowflake

package org.wso2.exampledocgen.image;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BString;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.Map;
import javax.imageio.ImageIO;

/**
 * Small Java ImageIO adapter for Ballerina image operations.
 */
public final class ImageKitBridge {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private ImageKitBridge() {
    }

    public static BString readInfo(BString path) {
        try {
            File file = new File(path.getValue());
            BufferedImage image = readImage(file);
            return success("info", Map.of("info", imageInfo(image, format(file))));
        } catch (IOException e) {
            return error(e);
        }
    }

    public static BString cropInPlace(BString path, BString cropBoxJson) {
        try {
            File file = new File(path.getValue());
            BufferedImage image = readImage(file);
            Map<String, Object> cropBox = MAPPER.readValue(cropBoxJson.getValue(), new TypeReference<>() {
            });
            int x = intField(cropBox, "x");
            int y = intField(cropBox, "y");
            int width = intField(cropBox, "width");
            int height = intField(cropBox, "height");
            validateCropBox(image, x, y, width, height);

            BufferedImage cropped = image.getSubimage(x, y, width, height);
            String format = format(file);
            if (!ImageIO.write(cropped, format, file)) {
                throw new IOException("No ImageIO writer found for format: " + format);
            }

            Map<String, Object> result = new LinkedHashMap<>();
            result.put("path", file.getPath());
            result.put("originalWidth", image.getWidth());
            result.put("originalHeight", image.getHeight());
            result.put("width", width);
            result.put("height", height);
            result.put("format", format);
            return success("result", Map.of("result", result));
        } catch (IOException | IllegalArgumentException e) {
            return error(e);
        }
    }

    private static BufferedImage readImage(File file) throws IOException {
        if (!file.isFile()) {
            throw new IOException("image file not found: " + file);
        }
        BufferedImage image = ImageIO.read(file);
        if (image == null) {
            throw new IOException("unsupported image file: " + file);
        }
        return image;
    }

    private static Map<String, Object> imageInfo(BufferedImage image, String format) {
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("width", image.getWidth());
        info.put("height", image.getHeight());
        info.put("format", format);
        return info;
    }

    private static String format(File file) {
        String name = file.getName();
        int index = name.lastIndexOf('.');
        return index >= 0 ? name.substring(index + 1).toLowerCase() : "png";
    }

    private static int intField(Map<String, Object> values, String key) {
        Object value = values.get(key);
        if (value instanceof Number number) {
            return number.intValue();
        }
        throw new IllegalArgumentException(key + " is required");
    }

    private static void validateCropBox(BufferedImage image, int x, int y, int width, int height) {
        if (x < 0 || y < 0 || width <= 0 || height <= 0) {
            throw new IllegalArgumentException("crop box values are out of range");
        }
        if (x + width > image.getWidth() || y + height > image.getHeight()) {
            throw new IllegalArgumentException("crop box exceeds image dimensions");
        }
    }

    private static BString success(String type, Map<String, Object> fields) {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("type", type);
        response.putAll(fields);
        return toJson(response);
    }

    private static BString error(Exception exception) {
        String message = exception.getMessage() == null ? exception.toString() : exception.getMessage();
        return success("error", Map.of("message", message));
    }

    private static BString toJson(Map<String, Object> response) {
        try {
            return StringUtils.fromString(MAPPER.writeValueAsString(response));
        } catch (JsonProcessingException e) {
            return StringUtils.fromString("{\"type\":\"error\",\"message\":\"could not serialize image response\"}");
        }
    }
}
