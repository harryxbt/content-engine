"""
Collage generator module.

Pure functions for:
- Picking random images from folders
- Building collage canvases with layouts
- Applying overlays and text
- Saving output images

Main entry points:
    generate_collage(caption, kind, setting_name) -> Path
    generate_batch(captions, setting_name, batch_id) -> list[SaveResult]
"""

import logging
import random
from pathlib import Path
from typing import Dict, List, Optional, Any

from PIL import Image, ImageDraw, ImageFont

from .config import Config, get_config
from .storage import StorageBackend, LocalStorageBackend, SaveResult

logger = logging.getLogger(__name__)


class GeneratorError(Exception):
    """Base exception for generator errors."""
    pass


class NoImagesError(GeneratorError):
    """Raised when a folder contains no valid images."""

    def __init__(self, folder: Path):
        self.folder = folder
        super().__init__(f"No images found in {folder}")


def pick_random_image(folder: Path, config: Optional[Config] = None) -> Path:
    """
    Pick a random image file from a folder.

    Args:
        folder: Path to folder containing images
        config: Configuration (for valid extensions)

    Returns:
        Path to a randomly selected image file

    Raises:
        NoImagesError: If folder contains no valid image files
    """
    config = config or get_config()

    if not folder.is_dir():
        raise NoImagesError(folder)

    valid_extensions = config.VALID_IMAGE_EXTENSIONS
    images = [
        f for f in folder.iterdir()
        if f.is_file() and f.suffix.lower() in valid_extensions
    ]

    if not images:
        raise NoImagesError(folder)

    return random.choice(images)


def pick_images_for_collage(
    kind: str,
    setting_name: str,
    config: Optional[Config] = None
) -> List[Path]:
    """
    Pick random images for a collage based on type and setting.

    Args:
        kind: "neg" or "pos"
        setting_name: Setting name (e.g., "default", "3s")
        config: Configuration instance

    Returns:
        List of paths to selected images (one per subfolder)

    Raises:
        NoImagesError: If any required subfolder has no images
    """
    config = config or get_config()

    root = config.get_root_for_type(kind)
    subfolders = config.get_subfolders(kind, setting_name)

    image_paths = []
    for subfolder in subfolders:
        folder_path = root / subfolder
        image_path = pick_random_image(folder_path, config)
        image_paths.append(image_path)

    return image_paths


def build_collage_image(
    image_paths: List[Path],
    caption: str,
    setting_config: Dict[str, Any],
    config: Optional[Config] = None
) -> Image.Image:
    """
    Build a collage image from source images.

    Args:
        image_paths: List of paths to source images
        caption: Text to overlay on the collage
        setting_config: Layout configuration dict
        config: Configuration instance

    Returns:
        PIL Image of the completed collage (RGBA mode)
    """
    config = config or get_config()

    canvas_size = tuple(setting_config["canvas_size"])
    image_size = tuple(setting_config["image_size"])
    layout = setting_config["layout"]

    # Create base canvas
    canvas = Image.new("RGB", canvas_size)

    # Place images according to layout
    if layout == "3s_split":
        # 3s layout: 2 square images on left (540x540), 1 portrait on right (540x1080)
        for i, path in enumerate(image_paths):
            img = Image.open(path)
            if i < 2:
                # First 2 images: left side, stacked vertically
                img = img.resize((540, 540))
                x = 0
                y = i * 540
            else:
                # Third image: right side, full height portrait
                img = img.resize((540, 1080))
                x = 540
                y = 0
            canvas.paste(img, (x, y))

    elif layout == "portrait":
        # Portrait layout: stack 3 images vertically (540x360 each)
        portrait_image_size = (540, 360)
        for i, path in enumerate(image_paths):
            img = Image.open(path).resize(portrait_image_size)
            x = 0
            y = i * 360
            canvas.paste(img, (x, y))

    else:
        # Default 2x2 grid layout
        for i, path in enumerate(image_paths):
            img = Image.open(path).resize(image_size)
            x = (i % 2) * image_size[0]
            y = (i // 2) * image_size[1]
            canvas.paste(img, (x, y))

    # Apply semi-transparent black overlay
    overlay = Image.new("RGBA", canvas_size, (0, 0, 0, config.OVERLAY_OPACITY))
    canvas = canvas.convert("RGBA")
    canvas = Image.alpha_composite(canvas, overlay)

    # Add centered caption text
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(str(config.font_path), config.FONT_SIZE)

    bbox = draw.textbbox((0, 0), caption, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]

    x = (canvas_size[0] - text_w) / 2
    y = (canvas_size[1] - text_h) / 2

    draw.text((x, y), caption, font=font, fill="white")

    return canvas


def generate_collage(
    caption: str,
    kind: str,
    setting_name: str = "default",
    config: Optional[Config] = None,
) -> Image.Image:
    """
    Generate a single collage image.

    This is the main entry point for creating one collage.

    Args:
        caption: Text to display on the collage
        kind: "neg" or "pos" - determines which image folders to use
        setting_name: Layout setting name (default: "default")
        config: Configuration instance

    Returns:
        PIL Image of the completed collage

    Raises:
        NoImagesError: If any required folder has no images
        ConfigError: If setting_name is invalid
        ValueError: If kind is not "neg" or "pos"
    """
    config = config or get_config()

    if kind not in ("neg", "pos"):
        raise ValueError(f"Invalid kind '{kind}'. Must be 'neg' or 'pos'.")

    # Get setting configuration
    setting_config = config.get_setting(setting_name)

    # Pick random images
    image_paths = pick_images_for_collage(kind, setting_name, config)

    logger.debug(
        f"Generating collage: kind={kind}, setting={setting_name}, "
        f"images={[p.name for p in image_paths]}"
    )

    # Build the collage
    collage = build_collage_image(image_paths, caption, setting_config, config)

    return collage


def generate_batch(
    captions: List[Dict[str, str]],
    setting_name: str = "default",
    batch_id: Optional[str] = None,
    config: Optional[Config] = None,
    storage: Optional[StorageBackend] = None,
) -> List[SaveResult]:
    """
    Generate a batch of collages and save them.

    Args:
        captions: List of dicts with "text" and "type" keys
            Example: [{"text": "caption here", "type": "neg"}, ...]
        setting_name: Layout setting name (default: "default")
        batch_id: Optional batch identifier. Generated if not provided.
        config: Configuration instance
        storage: Storage backend for saving. Uses LocalStorageBackend if not provided.

    Returns:
        List of SaveResult objects with paths and URLs

    Raises:
        NoImagesError: If any required folder has no images
        ConfigError: If setting_name is invalid
        ValueError: If any caption has invalid type

    Example:
        results = generate_batch([
            {"text": "road to hell", "type": "neg"},
            {"text": "road to heaven", "type": "pos"},
        ], setting_name="3s")
        for r in results:
            print(r.url)
    """
    config = config or get_config()
    storage = storage or LocalStorageBackend(config)

    if batch_id is None:
        batch_id = storage.generate_batch_id()

    logger.info(
        f"Starting batch generation: batch_id={batch_id}, "
        f"count={len(captions)}, setting={setting_name}"
    )

    results = []

    for i, caption_entry in enumerate(captions):
        text = caption_entry["text"]
        kind = caption_entry["type"]

        if kind not in ("neg", "pos"):
            raise ValueError(
                f"Invalid type '{kind}' in caption {i}. Must be 'neg' or 'pos'."
            )

        # Generate the collage image
        collage = generate_collage(text, kind, setting_name, config)

        # Create filename
        filename = f"{kind}_{i + 1}.png"

        # Save using storage backend
        result = storage.save(collage, batch_id, filename)
        results.append(result)

        logger.debug(f"Saved: {result.filename} -> {result.url}")

    logger.info(f"Batch complete: {len(results)} images generated")

    return results


def generate_batch_local(
    captions: List[Dict[str, str]],
    setting_name: str = "default",
    output_dir: Optional[Path] = None,
    config: Optional[Config] = None,
) -> List[Path]:
    """
    Generate a batch of collages and save to local paths (legacy mode).

    This matches the original script's output structure for local CLI usage.

    Args:
        captions: List of dicts with "text" and "type" keys
        setting_name: Layout setting name
        output_dir: Override output directory
        config: Configuration instance

    Returns:
        List of local file paths to generated images
    """
    config = config or get_config()

    if output_dir is None:
        output_dir = config.output_dir

    output_dir.mkdir(parents=True, exist_ok=True)
    setting_config = config.get_setting(setting_name)

    paths = []

    for i, entry in enumerate(captions):
        folder_index = (i // 2) + 1
        folder = output_dir / f"img_{folder_index}"
        folder.mkdir(parents=True, exist_ok=True)

        kind = entry["type"]
        caption = entry["text"]

        # Generate collage
        collage = generate_collage(caption, kind, setting_name, config)

        # Save locally
        filename = f"{kind}_{i + 1}.png"
        output_path = folder / filename
        collage.convert("RGB").save(output_path, format="PNG")

        print(f"Saved: {output_path}")
        paths.append(output_path)

    return paths
