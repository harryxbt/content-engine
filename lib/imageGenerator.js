const sharp = require('sharp');
const path = require('path');
const fs = require('fs');

// Layout settings (matching Python config)
const SETTINGS = {
  default: {
    neg_subfolders: ['alc', 'badfood', 'bumlife', 'dashboard'],
    pos_subfolders: ['atheletic', 'dashboard', 'food', 'money'],
    canvas_size: [1080, 1080],
    image_size: [540, 540],
    layout: '2x2'
  },
  '3s': {
    neg_subfolders: ['alc', 'bumlife', 'dashboard_portrait'],
    pos_subfolders: ['atheletic', 'food', 'dashboard_portrait'],
    canvas_size: [1080, 1080],
    image_size: [540, 540],
    layout: '3s_split'
  }
};

const OVERLAY_OPACITY = Math.round(255 * 0.44); // 112
const FONT_SIZE = 32;
const VALID_EXTENSIONS = ['.jpg', '.jpeg', '.png'];

/**
 * Pick a random image from a folder
 */
function pickRandomImage(folderPath) {
  if (!fs.existsSync(folderPath)) {
    throw new Error(`Folder not found: ${folderPath}`);
  }

  const files = fs.readdirSync(folderPath).filter(f => {
    const ext = path.extname(f).toLowerCase();
    return VALID_EXTENSIONS.includes(ext);
  });

  if (files.length === 0) {
    throw new Error(`No images found in: ${folderPath}`);
  }

  const randomFile = files[Math.floor(Math.random() * files.length)];
  return path.join(folderPath, randomFile);
}

/**
 * Pick images for a collage based on type and setting
 */
function pickImagesForCollage(kind, settingName, negRoot, posRoot) {
  const setting = SETTINGS[settingName];
  if (!setting) {
    throw new Error(`Unknown setting: ${settingName}. Available: ${Object.keys(SETTINGS).join(', ')}`);
  }

  const root = path.resolve(kind === 'neg' ? negRoot : posRoot);
  const subfolders = kind === 'neg' ? setting.neg_subfolders : setting.pos_subfolders;

  return subfolders.map(subfolder => {
    const folderPath = path.join(root, subfolder);
    return pickRandomImage(folderPath);
  });
}

/**
 * Create SVG text overlay
 */
function createTextSvg(text, width, height, fontSize = FONT_SIZE) {
  // Escape XML special characters
  const escaped = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');

  return Buffer.from(`
    <svg width="${width}" height="${height}">
      <style>
        .caption {
          font-family: sans-serif;
          font-size: ${fontSize}px;
          font-weight: 600;
          fill: white;
        }
      </style>
      <text
        x="50%"
        y="50%"
        text-anchor="middle"
        dominant-baseline="middle"
        class="caption"
      >${escaped}</text>
    </svg>
  `);
}

/**
 * Build a collage image from source images
 */
async function buildCollageImage(imagePaths, caption, settingConfig) {
  const [canvasWidth, canvasHeight] = settingConfig.canvas_size;
  const [imageWidth, imageHeight] = settingConfig.image_size;
  const layout = settingConfig.layout;

  // Prepare composite operations
  const composites = [];

  if (layout === '3s_split') {
    // 3s layout: 2 squares on left (540x540), 1 portrait on right (540x1080)
    for (let i = 0; i < imagePaths.length; i++) {
      const imgPath = imagePaths[i];
      let resized;
      let x, y;

      if (i < 2) {
        // First 2 images: left side, stacked vertically
        resized = await sharp(imgPath).resize(540, 540, { fit: 'cover' }).toBuffer();
        x = 0;
        y = i * 540;
      } else {
        // Third image: right side, full height portrait
        resized = await sharp(imgPath).resize(540, 1080, { fit: 'cover' }).toBuffer();
        x = 540;
        y = 0;
      }

      composites.push({ input: resized, left: x, top: y });
    }
  } else if (layout === 'portrait') {
    // Portrait layout: stack 3 images vertically (540x360 each)
    for (let i = 0; i < imagePaths.length; i++) {
      const imgPath = imagePaths[i];
      const resized = await sharp(imgPath).resize(540, 360, { fit: 'cover' }).toBuffer();
      composites.push({ input: resized, left: 0, top: i * 360 });
    }
  } else {
    // Default 2x2 grid layout
    for (let i = 0; i < imagePaths.length; i++) {
      const imgPath = imagePaths[i];
      const resized = await sharp(imgPath).resize(imageWidth, imageHeight, { fit: 'cover' }).toBuffer();
      const x = (i % 2) * imageWidth;
      const y = Math.floor(i / 2) * imageHeight;
      composites.push({ input: resized, left: x, top: y });
    }
  }

  // Create base canvas and composite images
  let canvas = sharp({
    create: {
      width: canvasWidth,
      height: canvasHeight,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 1 }
    }
  });

  canvas = await canvas.composite(composites).png().toBuffer();

  // Add semi-transparent black overlay
  const overlay = await sharp({
    create: {
      width: canvasWidth,
      height: canvasHeight,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: OVERLAY_OPACITY / 255 }
    }
  }).png().toBuffer();

  canvas = await sharp(canvas)
    .composite([{ input: overlay, blend: 'over' }])
    .png()
    .toBuffer();

  // Add centered caption text
  const textSvg = createTextSvg(caption, canvasWidth, canvasHeight, FONT_SIZE);
  canvas = await sharp(canvas)
    .composite([{ input: textSvg, blend: 'over' }])
    .png()
    .toBuffer();

  return canvas;
}

/**
 * Generate a single collage image
 */
async function generateCollage({ caption, kind, settingName = 'default', negRoot, posRoot }) {
  if (!['neg', 'pos'].includes(kind)) {
    throw new Error(`Invalid kind '${kind}'. Must be 'neg' or 'pos'.`);
  }

  const setting = SETTINGS[settingName];
  if (!setting) {
    throw new Error(`Unknown setting '${settingName}'. Available: ${Object.keys(SETTINGS).join(', ')}`);
  }

  // Pick random images
  const imagePaths = pickImagesForCollage(kind, settingName, negRoot, posRoot);

  // Build the collage
  return buildCollageImage(imagePaths, caption, setting);
}

/**
 * Generate a batch of collages
 */
async function generateBatch({ captions, settingName = 'default', batchId, outputDir, negRoot, posRoot, publicBaseUrl }) {
  const results = [];

  for (let i = 0; i < captions.length; i++) {
    const { text, type: kind } = captions[i];

    if (!['neg', 'pos'].includes(kind)) {
      throw new Error(`Invalid type '${kind}' in caption ${i}. Must be 'neg' or 'pos'.`);
    }

    // Generate the collage
    const imageBuffer = await generateCollage({
      caption: text,
      kind,
      settingName,
      negRoot,
      posRoot
    });

    // Create filename and save
    const filename = `${batchId}_${kind}_${i + 1}.png`;
    const outputPath = path.join(outputDir, filename);

    await sharp(imageBuffer).toFile(outputPath);

    const url = `${publicBaseUrl}/output/${filename}`;

    results.push({
      caption: text,
      type: kind,
      filename,
      url
    });
  }

  return results;
}

module.exports = {
  generateCollage,
  generateBatch,
  SETTINGS,
  pickRandomImage
};
