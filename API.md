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
  "url": "https://content-engine-production-ce86.up.railway.app/output/video_HighLow_cab7d47a.mp4"
}
```

---

## Error Responses

All errors return this format:
```json
{
  "error": "ERROR_CODE",
  "detail": "Human readable message"
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
  "detail": "Video 'Unknown.mp4' not found in library"
}
```

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

### Example n8n IF Node Condition
```
{{ $json.error }} is not empty → Error path
{{ $json.url }} is not empty → Success path
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
