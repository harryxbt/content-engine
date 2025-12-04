const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// Constants
const OUTPUT_WIDTH = 1080;
const OUTPUT_HEIGHT = 1920;
const BANNER_HEIGHT = 346;
const VIDEO_TOP_OFFSET = 325;
const TRIM_START = 0;
const TRIM_END = 0;

/**
 * Get video info using ffprobe
 */
function getVideoInfo(inputPath) {
  return new Promise((resolve, reject) => {
    const ffprobe = spawn('ffprobe', [
      '-v', 'error',
      '-select_streams', 'v:0',
      '-show_entries', 'stream=width,height,duration',
      '-show_entries', 'format=duration',
      '-of', 'json',
      inputPath
    ]);

    let output = '';
    ffprobe.stdout.on('data', (data) => { output += data; });
    ffprobe.stderr.on('data', (data) => { console.error('[ffprobe]', data.toString()); });

    ffprobe.on('close', (code) => {
      if (code === 0) {
        try {
          const info = JSON.parse(output);
          const duration = parseFloat(info.format?.duration || info.streams?.[0]?.duration || 30);
          resolve({ duration });
        } catch (e) {
          reject(new Error(`Failed to parse ffprobe output: ${e.message}`));
        }
      } else {
        reject(new Error(`ffprobe exited with code ${code}`));
      }
    });
  });
}

/**
 * Wrap text to fit within a given character width
 */
function wrapText(text, maxCharsPerLine = 30) {
  const words = text.split(' ');
  const lines = [];
  let currentLine = '';

  for (const word of words) {
    if (currentLine.length + word.length + 1 <= maxCharsPerLine) {
      currentLine = currentLine ? `${currentLine} ${word}` : word;
    } else {
      if (currentLine) lines.push(currentLine);
      currentLine = word;
    }
  }
  if (currentLine) lines.push(currentLine);

  return lines;
}

/**
 * Escape text for ffmpeg drawtext filter
 */
function escapeText(text) {
  return text
    .replace(/\\/g, '\\\\\\\\')
    .replace(/'/g, "\\'")
    .replace(/:/g, '\\:')
    .replace(/\[/g, '\\[')
    .replace(/\]/g, '\\]');
}

/**
 * Generate video with banner overlay using pure ffmpeg
 */
async function generateVideo({ inputPath, outputPath, caption, fontPath }) {
  // Get video info
  const { duration } = await getVideoInfo(inputPath);
  const trimmedDuration = Math.max(1, duration - TRIM_START - TRIM_END);

  console.log(`[video] Duration: ${duration}s, trimmed: ${trimmedDuration}s`);

  // Check if font exists, use fallback if not
  let fontFile = fontPath;
  if (!fs.existsSync(fontPath)) {
    // Try common fallback locations
    const fallbacks = [
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/System/Library/Fonts/Helvetica.ttc',
      '/System/Library/Fonts/SFNSText.ttf'
    ];
    fontFile = fallbacks.find(f => fs.existsSync(f)) || 'sans';
  }

  const videoAreaHeight = OUTPUT_HEIGHT - VIDEO_TOP_OFFSET;

  // Wrap caption into multiple lines if needed
  const lines = wrapText(caption, 28);
  const lineHeight = 60;
  const totalTextHeight = lines.length * lineHeight;
  const startY = (BANNER_HEIGHT - totalTextHeight) / 2;

  // Build ffmpeg filter:
  // 1. Scale video to fit width (1080), height scales proportionally
  // 2. Pad/crop to exact size needed for video area
  // 3. Create black background
  // 4. Place video at offset from top
  // 5. Create white banner with text (multiple lines)
  // 6. Overlay banner at top
  const filterParts = [
    // Scale video to fit width, then crop height from center to fit video area
    `[0:v]scale=${OUTPUT_WIDTH}:-1,crop=${OUTPUT_WIDTH}:${videoAreaHeight}:0:(ih-${videoAreaHeight})/2,setsar=1[scaled]`,

    // Create black background
    `color=black:s=${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}:d=${trimmedDuration}:r=30[bg]`,

    // Create white banner
    `color=white:s=${OUTPUT_WIDTH}x${BANNER_HEIGHT}:d=${trimmedDuration}:r=30[banner_bg]`
  ];

  // Add drawtext for each line
  let lastBannerLabel = 'banner_bg';
  lines.forEach((line, i) => {
    const escapedLine = escapeText(line);
    const y = Math.round(startY + (i * lineHeight) + lineHeight / 2);
    const newLabel = i === lines.length - 1 ? 'banner' : `banner_${i}`;
    filterParts.push(
      `[${lastBannerLabel}]drawtext=fontfile='${fontFile}':text='${escapedLine}':fontsize=48:fontcolor=black:x=(w-text_w)/2:y=${y}-th/2[${newLabel}]`
    );
    lastBannerLabel = newLabel;
  });

  filterParts.push(
    // Overlay video on black background at offset position
    `[bg][scaled]overlay=0:${VIDEO_TOP_OFFSET}:shortest=1[with_video]`,

    // Overlay banner at top
    `[with_video][banner]overlay=0:0[composed]`,

    // Add 1 second fade in from black
    `[composed]fade=t=in:st=0:d=1[out]`
  );

  const filterComplex = filterParts.join(';');

  return new Promise((resolve, reject) => {
    const args = [
      '-y',
      '-ss', String(TRIM_START),           // Seek to trim start (fast seek)
      '-i', inputPath,                      // Input video
      '-filter_complex', filterComplex,
      '-map', '[out]',                      // Map video output
      '-map', '0:a?',                       // Map audio if exists
      '-t', String(trimmedDuration),        // Output duration
      '-c:v', 'libx264',
      '-preset', 'fast',
      '-crf', '23',
      '-c:a', 'aac',
      '-b:a', '128k',
      '-ar', '44100',
      '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart',
      outputPath
    ];

    console.log('[ffmpeg] Running with filter_complex...');
    console.log('[ffmpeg] Input:', inputPath);
    console.log('[ffmpeg] Output:', outputPath);

    const ffmpeg = spawn('ffmpeg', args);

    let stderr = '';
    ffmpeg.stderr.on('data', (data) => {
      stderr += data.toString();
      const str = data.toString();
      // Log progress
      if (str.includes('frame=')) {
        const match = str.match(/frame=\s*(\d+)/);
        if (match) {
          process.stdout.write(`[ffmpeg] Frame ${match[1]}\r`);
        }
      }
    });

    ffmpeg.on('close', (code) => {
      console.log('');
      if (code === 0) {
        console.log('[ffmpeg] Success:', outputPath);
        resolve(outputPath);
      } else {
        console.error('[ffmpeg] Failed with code:', code);
        console.error('[ffmpeg] Last stderr:', stderr.slice(-2000));
        reject(new Error(`ffmpeg failed: ${stderr.slice(-500)}`));
      }
    });

    ffmpeg.on('error', (err) => {
      reject(new Error(`ffmpeg spawn error: ${err.message}`));
    });
  });
}

module.exports = { generateVideo };
