const express = require('express');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const { generateVideo } = require('./lib/videoGenerator');

const app = express();
app.use(express.json());

// Request ID middleware
app.use((req, res, next) => {
  req.requestId = uuidv4().substring(0, 8);
  req.startTime = Date.now();
  next();
});

// Config
const PORT = process.env.PORT || 8000;
const OUTPUT_DIR = process.env.OUTPUT_DIR || './output';
const LIBRARY_PATH = process.env.LIBRARY_PATH || './library';
const FONT_PATH = process.env.FONT_PATH || './fonts/tiktok-sans-scm.ttf';
const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || `http://localhost:${PORT}`;

// Ensure output dir exists
if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

// Serve output files
app.use('/output', express.static(OUTPUT_DIR));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Debug ffmpeg
app.get('/debug-ffmpeg', async (req, res) => {
  const { execSync } = require('child_process');

  let ffmpegVersion = 'unknown';
  let whichFfmpeg = 'not found';
  let libraryFiles = [];

  try {
    whichFfmpeg = execSync('which ffmpeg').toString().trim();
  } catch (e) {}

  try {
    ffmpegVersion = execSync('ffmpeg -version').toString().split('\n')[0];
  } catch (e) {}

  try {
    libraryFiles = fs.readdirSync(LIBRARY_PATH);
  } catch (e) {}

  res.json({
    which_ffmpeg: whichFfmpeg,
    ffmpeg_version: ffmpegVersion,
    library_path: path.resolve(LIBRARY_PATH),
    library_files: libraryFiles,
    node_version: process.version
  });
});

// Generate video endpoint
app.post('/generate-video', async (req, res) => {
  const { scenario, caption, video_url } = req.body;
  const requestId = req.requestId;
  const timestamp = new Date().toISOString();

  // Structured log helper
  const log = (level, msg, data = {}) => {
    console.log(JSON.stringify({
      level,
      requestId,
      timestamp: new Date().toISOString(),
      msg,
      ...data
    }));
  };

  // Helper to build _meta
  const buildMeta = (extra = {}) => ({
    requestId,
    timestamp,
    durationMs: Date.now() - req.startTime,
    ...extra
  });

  if (!scenario || !caption) {
    log('warn', 'Missing required parameters', { scenario: !!scenario, caption: !!caption });
    return res.status(400).json({
      error: 'MISSING_PARAMS',
      detail: 'scenario and caption are required',
      _meta: buildMeta({ failedStep: 'validate' })
    });
  }

  log('info', 'Starting video generation', { scenario, captionLength: caption.length });

  try {
    // Determine input video path
    let inputPath;
    if (video_url) {
      inputPath = video_url;
      log('info', 'Using external video URL', { video_url });
    } else {
      inputPath = path.join(LIBRARY_PATH, `${scenario}.mp4`);
      if (!fs.existsSync(inputPath)) {
        log('error', 'Video not found in library', { scenario, path: inputPath });
        return res.status(404).json({
          error: 'VIDEO_NOT_FOUND',
          detail: `Video '${scenario}.mp4' not found in library`,
          _meta: buildMeta({ failedStep: 'lookup' })
        });
      }
    }

    // Generate output filename
    const videoId = uuidv4().substring(0, 8);
    const filename = `video_${scenario}_${videoId}.mp4`;
    const outputPath = path.join(OUTPUT_DIR, filename);

    // Generate the video (now returns { outputPath, metrics })
    const result = await generateVideo({
      inputPath,
      outputPath,
      caption,
      fontPath: FONT_PATH
    });

    const url = `${PUBLIC_BASE_URL}/output/${filename}`;

    log('info', 'Video generation complete', {
      filename,
      durationMs: result.metrics.totalDurationMs,
      videoDurationSec: result.metrics.videoDurationSec
    });

    res.json({
      scenario,
      caption,
      filename,
      url,
      _meta: buildMeta({
        steps: result.metrics.steps,
        videoDurationSec: result.metrics.videoDurationSec
      })
    });

  } catch (error) {
    log('error', 'Video generation failed', { error: error.message });
    res.status(500).json({
      error: 'VIDEO_GENERATION_FAILED',
      detail: error.message,
      _meta: buildMeta({ failedStep: 'ffmpeg' })
    });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Content Engine API running on port ${PORT}`);
  console.log(`Output dir: ${path.resolve(OUTPUT_DIR)}`);
  console.log(`Library: ${path.resolve(LIBRARY_PATH)}`);
});
