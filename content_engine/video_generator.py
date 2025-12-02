"""
Video Generator Module

Generates TikTok-ready videos with banner overlays from a library of templates.
"""

import os
import subprocess
import tempfile
import textwrap
from pathlib import Path
from typing import Optional

from moviepy import VideoFileClip, ImageClip, CompositeVideoClip, ColorClip, vfx
from moviepy.config import change_settings
from PIL import Image, ImageDraw, ImageFont
import numpy as np

# Explicitly set ffmpeg path for MoviePy (Railway uses static build)
FFMPEG_PATH = os.environ.get("IMAGEIO_FFMPEG_EXE", "/usr/local/bin/ffmpeg")
if os.path.exists(FFMPEG_PATH):
    change_settings({"FFMPEG_BINARY": FFMPEG_PATH})


# Constants
OUTPUT_WIDTH = 1080
OUTPUT_HEIGHT = 1920
BANNER_HEIGHT = 346  # 18% of 1920
VIDEO_TOP_OFFSET = 155  # Push video down 155px below banner
TRIM_START_SECONDS = 5  # Cut first 5 seconds of video
TRIM_END_SECONDS = 1  # Cut last 1 second of video
PADDING = 40  # Horizontal padding for text


class VideoNotFoundError(Exception):
    """Raised when a video scenario is not found in the library."""
    def __init__(self, scenario: str, library_path: Path):
        self.scenario = scenario
        self.library_path = library_path
        super().__init__(f"Video '{scenario}.mp4' not found in {library_path}")


def create_banner_image(
    caption: str,
    font_path: Path,
    width: int = OUTPUT_WIDTH,
    height: int = BANNER_HEIGHT
) -> np.ndarray:
    """
    Create a white banner with centered caption text.

    Args:
        caption: Text to display
        font_path: Path to the font file
        width: Banner width in pixels
        height: Banner height in pixels

    Returns:
        numpy array of the banner image (RGB)
    """
    # Create white background
    img = Image.new("RGB", (width, height), color=(255, 255, 255))
    draw = ImageDraw.Draw(img)

    # Available width for text (with padding)
    max_text_width = width - (PADDING * 2)
    max_text_height = height - (PADDING * 2)

    # Find optimal font size with text wrapping
    font_size = 60  # Start smaller
    min_font_size = 20

    font = None
    wrapped_text = caption

    while font_size >= min_font_size:
        try:
            font = ImageFont.truetype(str(font_path), font_size)
        except OSError:
            # Fallback to default font if custom font fails
            font = ImageFont.load_default()
            break

        # Try to wrap text to fit width
        avg_char_width = font_size * 0.6  # Approximate
        chars_per_line = int(max_text_width / avg_char_width)
        chars_per_line = max(10, chars_per_line)  # Minimum 10 chars per line

        wrapped_text = textwrap.fill(caption, width=chars_per_line)

        # Measure text bounding box
        bbox = draw.textbbox((0, 0), wrapped_text, font=font)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]

        # Check if text fits
        if text_width <= max_text_width and text_height <= max_text_height:
            break

        font_size -= 4

    # Calculate centered position
    bbox = draw.textbbox((0, 0), wrapped_text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]

    x = (width - text_width) / 2
    y = (height - text_height) / 2

    # Draw text (black color)
    draw.text((x, y), wrapped_text, font=font, fill=(0, 0, 0), align="center")

    return np.array(img)


def resize_video_to_tiktok(clip: VideoFileClip) -> VideoFileClip:
    """
    Resize and crop video to 1080x1920 TikTok format.

    Strategy:
    - Scale to fit width (1080px)
    - Center crop to fit height (1920px)
    - If video is shorter than 1920, scale to fit height instead and crop width
    """
    orig_w, orig_h = clip.size
    target_w, target_h = OUTPUT_WIDTH, OUTPUT_HEIGHT
    target_aspect = target_w / target_h  # 0.5625
    orig_aspect = orig_w / orig_h

    if orig_aspect > target_aspect:
        # Video is wider than target - fit to height, crop width
        new_height = target_h
        new_width = int(orig_w * (target_h / orig_h))
        clip = clip.resized(height=new_height)
        # Center crop width
        x_center = new_width / 2
        x1 = int(x_center - target_w / 2)
        clip = clip.cropped(x1=x1, x2=x1 + target_w, y1=0, y2=target_h)
    else:
        # Video is taller than target (or equal) - fit to width, crop height
        new_width = target_w
        new_height = int(orig_h * (target_w / orig_w))
        clip = clip.resized(width=new_width)
        # Center crop height
        y_center = new_height / 2
        y1 = int(y_center - target_h / 2)
        # Clamp y1 to valid range
        y1 = max(0, min(y1, new_height - target_h))
        clip = clip.cropped(x1=0, x2=target_w, y1=y1, y2=y1 + target_h)

    return clip


def generate_video(
    scenario: str,
    caption: str,
    output_path: Path,
    font_path: Path,
    video_url: Optional[str] = None,
    library_path: Optional[Path] = None,
    trim_start: float = 0,
    trim_end: float = 0,
) -> Path:
    """
    Generate a TikTok video with banner overlay from a library template.

    Args:
        scenario: Name of the video template (e.g., "high-low")
        caption: Text to display in the banner
        output_path: Path where the generated video will be saved
        font_path: Path to the font file
        video_url: URL to download the video from (preferred)
        library_path: Path to the video library folder (fallback)
        trim_start: Seconds to trim from start (default: 0)
        trim_end: Seconds to trim from end (default: 0)

    Returns:
        Path to the generated video file

    Raises:
        VideoNotFoundError: If the scenario video doesn't exist
    """
    temp_video_path = None

    if video_url:
        # Use ffmpeg to download and remux (handles HTTP better than curl/urllib)
        temp_video_path = tempfile.NamedTemporaryFile(suffix='.mp4', delete=False).name
        try:
            result = subprocess.run(
                [FFMPEG_PATH, '-y', '-i', video_url, '-c', 'copy', temp_video_path],
                capture_output=True,
                timeout=120
            )
            # Verify file was created and has content
            file_size = os.path.getsize(temp_video_path)
            if result.returncode != 0 or file_size < 1000:
                raise Exception(f"ffmpeg download failed: {result.stderr.decode()[:200]}")
        except Exception as e:
            if os.path.exists(temp_video_path):
                os.unlink(temp_video_path)
            raise VideoNotFoundError(scenario, Path(video_url))
        video_file = temp_video_path
    elif library_path:
        # Use local file
        video_file = library_path / f"{scenario}.mp4"
        if not video_file.is_file():
            raise VideoNotFoundError(scenario, library_path)
        video_file = str(video_file)
    else:
        raise ValueError("Either video_url or library_path must be provided")

    try:
        # Load video
        video = VideoFileClip(video_file)
        original_fps = video.fps

        # Trim first N seconds and last M seconds
        total_trim = trim_start + trim_end
        if video.duration > total_trim:
            video = video.subclipped(trim_start, video.duration - trim_end)

        # Get audio after trim
        original_audio = video.audio

        # Resize to TikTok format
        video = resize_video_to_tiktok(video)

        # Create banner
        banner_array = create_banner_image(caption, font_path)
        banner_clip = ImageClip(banner_array).with_duration(video.duration)

        # Position banner at top (0, 0)
        banner_clip = banner_clip.with_position((0, 0))

        # Position video with offset from top
        video = video.with_position((0, VIDEO_TOP_OFFSET))

        # Create black background
        background = ColorClip(
            size=(OUTPUT_WIDTH, OUTPUT_HEIGHT),
            color=(0, 0, 0)
        ).with_duration(video.duration)

        # Composite: background, then video (offset), then banner on top
        final = CompositeVideoClip(
            [background, video, banner_clip],
            size=(OUTPUT_WIDTH, OUTPUT_HEIGHT)
        )

        # Add 1-second fade in from black
        final = final.with_effects([vfx.FadeIn(1.0)])

        # Preserve audio
        if original_audio is not None:
            final = final.with_audio(original_audio)

        # Export (use fast preset and single thread to reduce memory on Railway)
        final.write_videofile(
            str(output_path),
            fps=original_fps,
            codec="libx264",
            audio_codec="aac",
            preset="ultrafast",
            threads=1,
            logger=None,  # Suppress moviepy progress output
        )

        # Cleanup
        video.close()
        final.close()

        return output_path

    finally:
        # Delete temp file if we downloaded from URL
        if temp_video_path and os.path.exists(temp_video_path):
            os.unlink(temp_video_path)
