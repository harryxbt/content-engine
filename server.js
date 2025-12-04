const express = require('express');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const { generateVideo } = require('./lib/videoGenerator');
const { generateBatch, SETTINGS } = require('./lib/imageGenerator');

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
const NEG_ROOT = process.env.NEG_ROOT || './negatives';
const POS_ROOT = process.env.POS_ROOT || './positives';

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

// Generate collage images endpoint
app.post('/generate', async (req, res) => {
  const { captions, setting = 'default', batch_id } = req.body;
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

  // Validate captions
  if (!captions || !Array.isArray(captions) || captions.length === 0) {
    log('warn', 'Missing or invalid captions', { captions: !!captions });
    return res.status(400).json({
      error: 'INVALID_CAPTIONS',
      detail: 'captions must be a non-empty array',
      _meta: buildMeta({ failedStep: 'validate' })
    });
  }

  // Validate each caption
  for (let i = 0; i < captions.length; i++) {
    const cap = captions[i];
    if (!cap.text || !cap.type) {
      return res.status(400).json({
        error: 'INVALID_CAPTION',
        detail: `Caption at index ${i} must have 'text' and 'type' fields`,
        _meta: buildMeta({ failedStep: 'validate' })
      });
    }
    if (!['neg', 'pos'].includes(cap.type)) {
      return res.status(400).json({
        error: 'INVALID_TYPE',
        detail: `Caption at index ${i} has invalid type '${cap.type}'. Must be 'neg' or 'pos'.`,
        _meta: buildMeta({ failedStep: 'validate' })
      });
    }
  }

  // Validate setting
  if (!SETTINGS[setting]) {
    return res.status(400).json({
      error: 'INVALID_SETTING',
      detail: `Unknown setting '${setting}'. Available: ${Object.keys(SETTINGS).join(', ')}`,
      _meta: buildMeta({ failedStep: 'validate' })
    });
  }

  const batchId = batch_id || uuidv4().substring(0, 8);
  log('info', 'Starting collage generation', { batchId, count: captions.length, setting });

  try {
    const results = await generateBatch({
      captions,
      settingName: setting,
      batchId,
      outputDir: OUTPUT_DIR,
      negRoot: NEG_ROOT,
      posRoot: POS_ROOT,
      publicBaseUrl: PUBLIC_BASE_URL
    });

    log('info', 'Collage generation complete', { batchId, count: results.length });

    res.json({
      batch_id: batchId,
      count: results.length,
      images: results,
      _meta: buildMeta()
    });

  } catch (error) {
    log('error', 'Collage generation failed', { error: error.message });
    res.status(500).json({
      error: 'GENERATION_FAILED',
      detail: error.message,
      _meta: buildMeta({ failedStep: 'generate' })
    });
  }
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
