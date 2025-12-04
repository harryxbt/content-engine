# Content Engine API

**Base URL:** `https://content-engine-production-ce86.up.railway.app`

---

## Endpoints

### Health Check
```
GET /health
```
**Response:**
```json
{"status": "ok"}
```

---

### Generate Video
```
POST /generate-video
Content-Type: application/json
```

**Request Body:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `scenario` | string | Yes | Video template name (matches filename in library, e.g., `HighLow`) |
| `caption` | string | Yes | Text to display on the white banner (auto-wraps long text) |
| `video_url` | string | No | External video URL (overrides scenario library lookup) |

**Example Request:**
```json
{
  "scenario": "HighLow",
  "caption": "POV: you and your bro are locking in this winter"
}
```

**Success Response (200):**
```json
{
  "scenario": "HighLow",
  "caption": "POV: you and your bro are locking in this winter",
  "filename": "video_HighLow_cab7d47a.mp4",
  "url": "https://content-engine-production-ce86.up.railway.app/output/video_HighLow_cab7d47a.mp4",
  "_meta": {
    "requestId": "abc12345",
    "timestamp": "2025-12-04T12:00:00.000Z",
    "durationMs": 6500,
    "steps": [
      {"step": "ffprobe", "durationMs": 200},
      {"step": "ffmpeg", "durationMs": 6200}
    ],
    "videoDurationSec": 30
  }
}
```

---

## Response Metadata (`_meta`)

All responses include a `_meta` object for tracking and debugging:

| Field | Type | Description |
|-------|------|-------------|
| `requestId` | string | Unique 8-char ID for this request |
| `timestamp` | string | ISO timestamp when request started |
| `durationMs` | number | Total processing time in milliseconds |
| `steps` | array | Breakdown of processing steps with timing |
| `videoDurationSec` | number | Duration of output video (success only) |
| `failedStep` | string | Which step failed (errors only) |

---

## Error Responses

All errors return this format:
```json
{
  "error": "ERROR_CODE",
  "detail": "Human readable message",
  "_meta": {
    "requestId": "abc12345",
    "timestamp": "2025-12-04T12:00:00.000Z",
    "durationMs": 150,
    "failedStep": "ffmpeg"
  }
}
```

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `MISSING_PARAMS` | 400 | Missing required `scenario` or `caption` |
| `VIDEO_NOT_FOUND` | 404 | Scenario video not found in library |
| `VIDEO_GENERATION_FAILED` | 500 | ffmpeg processing failed |

**Example Error:**
```json
{
  "error": "VIDEO_NOT_FOUND",
  "detail": "Video 'Unknown.mp4' not found in library",
  "_meta": {
    "requestId": "def67890",
    "timestamp": "2025-12-04T12:00:00.000Z",
    "durationMs": 5,
    "failedStep": "lookup"
  }
}
```

### Failed Steps Reference

| `failedStep` | Description |
|--------------|-------------|
| `validate` | Missing required parameters |
| `lookup` | Video file not found in library |
| `ffmpeg` | Video processing/encoding failed |

---

## n8n Integration

### HTTP Request Node Setup

1. **Method:** POST
2. **URL:** `https://content-engine-production-ce86.up.railway.app/generate-video`
3. **Headers:** `Content-Type: application/json`
4. **Body (JSON):**
```json
{
  "scenario": "{{ $json.scenario }}",
  "caption": "{{ $json.caption }}"
}
```

### Handling Response in n8n

**Success path:** Access `$json.url` to get the video download URL

**Error handling:** Check for `$json.error` field
- If exists: Handle error based on `$json.error` code
- If not: Video generated successfully

### Useful n8n Expressions

| Expression | Description |
|------------|-------------|
| `{{ $json.url }}` | Video download URL |
| `{{ $json.error }}` | Error code (null on success) |
| `{{ $json._meta.requestId }}` | Request ID for debugging |
| `{{ $json._meta.durationMs }}` | Processing time (ms) |
| `{{ $json._meta.failedStep }}` | Which step failed (errors) |

### Example n8n IF Node Condition
```
{{ $json.error }} is not empty → Error path
{{ $json.url }} is not empty → Success path
```

### Logging in n8n Code Node
```javascript
// Access metadata for logging
const meta = $json._meta;
console.log(`[${meta.requestId}] Completed in ${meta.durationMs}ms`);
if ($json.error) {
  console.error(`[${meta.requestId}] Failed at: ${meta.failedStep}`);
}
```

---

## Available Scenarios

Videos in library (case-sensitive):
- `HighLow` - High/Low comparison template

---

## Debug Endpoint

```
GET /debug-ffmpeg
```
Returns ffmpeg version, path, and library contents for troubleshooting.
