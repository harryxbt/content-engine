# Content Engine - Railway Deployment Session Notes

## Session Summary (Dec 2, 2025)

Fixed video generation API endpoint on Railway that was crashing with "MoviePy error: failed to read the first frame of video file".

---

## What Was Fixed

### 1. Import Crash - `moviepy.config`
**Problem:** Server crashed on startup with:
```
ImportError: cannot import name 'change_settings' from 'moviepy.config'
```

**Solution:** Removed the incompatible MoviePy 1.x config import. MoviePy 2.x doesn't have `change_settings`.

**Commit:** `674003e` - "Fix import crash - remove moviepy.config"

### 2. Static ffmpeg Build
**Problem:** Railway's default ffmpeg lacked proper codec support.

**Solution:** Dockerfile now installs static ffmpeg build from johnvansickle.com with all codecs:
```dockerfile
RUN curl -L https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz -o /tmp/ffmpeg.tar.xz \
    && tar -xf /tmp/ffmpeg.tar.xz -C /tmp \
    && mv /tmp/ffmpeg-*-amd64-static/ffmpeg /usr/local/bin/ \
    && mv /tmp/ffmpeg-*-amd64-static/ffprobe /usr/local/bin/
```

**Commit:** `d2d6eb9` - "Use static ffmpeg build with all codecs"

### 3. Better Error Handling
**Problem:** ffmpeg errors were being swallowed, showing only "Video not found".

**Solution:** Updated `VideoNotFoundError` to include actual error details:
```python
raise VideoNotFoundError(scenario, video_url, str(e))
```

**Commits:**
- `229b2e5` - "Fix VideoNotFoundError to show actual ffmpeg error"
- `4bbab67` - "Improve ffmpeg error logging"

---

## Current Working Setup

### API Endpoints
- `GET /health` - Health check
- `GET /debug-ffmpeg` - Debug ffmpeg configuration
- `POST /generate` - Generate image collages
- `POST /generate-video` - Generate videos with banner overlay

### Video Generation (Working)
```bash
curl -X POST https://content-engine-production-ce86.up.railway.app/generate-video \
  -H "Content-Type: application/json" \
  -d '{"scenario":"HighLow","caption":"Your caption here"}'
```

### Available Scenarios
- `HighLow` - library/HighLow.mp4
- `LowHigh` - library/LowHigh.mp4

---

## Known Issues

### CDN Download Not Working
Downloading videos from CDN URLs fails on Railway. The `video_url` parameter doesn't work.

**Workaround:** Use local library instead (don't pass `video_url`).

### Static Frame Issue (Under Investigation)
User reported video output shows only a static frame. Local testing shows 471 frames at 60fps correctly. May be Railway-specific or playback issue.

---

## Git Repository

**Remote:** `https://github.com/harryxbt/content-engine.git`
**Branch:** `main`

### Recent Commits
```
963ef9b Trigger redeploy
4bbab67 Improve ffmpeg error logging
229b2e5 Fix VideoNotFoundError to show actual ffmpeg error
6b8e9d8 Force redeploy - trigger Railway rebuild
674003e Fix import crash - remove moviepy.config
6c570f8 Explicit MoviePy ffmpeg config, reduce memory usage
7e73539 Use ffmpeg for URL downloads (handles HTTP better)
17b4d0c Add debug-ffmpeg endpoint
d2d6eb9 Use static ffmpeg build with all codecs
```

---

## Key Files

- `content_engine/video_generator.py` - Video processing with MoviePy
- `api/main.py` - FastAPI endpoints
- `Dockerfile` - Docker config with static ffmpeg
- `library/` - Source video templates (HighLow.mp4, LowHigh.mp4)

---

## Next Steps

1. Investigate static frame issue on Railway
2. Debug CDN download if needed (currently using local library)
3. Add more video templates to `library/` folder as needed
