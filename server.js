const express = require('express');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const { generateVideo } = require('./lib/videoGenerator');

const app = express();
app.use(express.json());

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

  if (!scenario || !caption) {
    return res.status(400).json({
      error: 'MISSING_PARAMS',
      detail: 'scenario and caption are required'
    });
  }

  console.log(`[generate-video] scenario=${scenario}, caption="${caption.substring(0, 50)}..."`);

  try {
    // Determine input video path
    let inputPath;
    if (video_url) {
      inputPath = video_url;
    } else {
      inputPath = path.join(LIBRARY_PATH, `${scenario}.mp4`);
      if (!fs.existsSync(inputPath)) {
        return res.status(404).json({
          error: 'VIDEO_NOT_FOUND',
          detail: `Video '${scenario}.mp4' not found in library`
        });
      }
    }

    // Generate output filename
    const videoId = uuidv4().substring(0, 8);
    const filename = `video_${scenario}_${videoId}.mp4`;
    const outputPath = path.join(OUTPUT_DIR, filename);

    // Generate the video
    await generateVideo({
      inputPath,
      outputPath,
      caption,
      fontPath: FONT_PATH
    });

    const url = `${PUBLIC_BASE_URL}/output/${filename}`;

    console.log(`[generate-video] Success: ${filename}`);

    res.json({
      scenario,
      caption,
      filename,
      url
    });

  } catch (error) {
    console.error('[generate-video] Error:', error);
    res.status(500).json({
      error: 'VIDEO_GENERATION_FAILED',
      detail: error.message
    });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Content Engine API running on port ${PORT}`);
  console.log(`Output dir: ${path.resolve(OUTPUT_DIR)}`);
  console.log(`Library: ${path.resolve(LIBRARY_PATH)}`);
});
