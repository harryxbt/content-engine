#!/usr/bin/env python3
"""
Video Banner Overlay Script

Adds a white banner with caption text to the top of any video.
Outputs TikTok-ready 1080x1920 vertical video.

Usage:
    python video_banner.py --input video.mp4 --output output.mp4 --caption "Your text here"

Example:
    python video_banner.py --input myvideo.mp4 --output final.mp4 --caption "Follow for more tips! 🔥"
"""

import argparse
import os
import sys
import textwrap
from pathlib import Path

from moviepy import VideoFileClip, ImageClip, CompositeVideoClip, ColorClip
from PIL import Image, ImageDraw, ImageFont
import numpy as np

# Constants
OUTPUT_WIDTH = 1080
OUTPUT_HEIGHT = 1920
BANNER_HEIGHT = 346  # 18% of 1920
VIDEO_TOP_OFFSET = 120  # Push video down 120px below banner
TRIM_START_SECONDS = 5  # Cut first 5 seconds of video
TRIM_END_SECONDS = 1  # Cut last 1 second of video
FONT_PATH = Path(__file__).parent / "fonts" / "tiktok-sans-scm.ttf"
PADDING = 40  # Horizontal padding for text


def create_banner_image(caption: str, width: int = OUTPUT_WIDTH, height: int = BANNER_HEIGHT) -> np.ndarray:
    """
    Create a white banner with centered caption text.

    Args:
        caption: Text to display
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
    font_size = 80  # Start large
    min_font_size = 24

    font = None
    wrapped_text = caption

    while font_size >= min_font_size:
        try:
            font = ImageFont.truetype(str(FONT_PATH), font_size)
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


def add_banner_to_video(input_path: str, output_path: str, caption: str) -> None:
    """
    Add a white banner with caption text to the top of a video.

    Args:
        input_path: Path to input video file
        output_path: Path for output video file
        caption: Text to display in the banner
    """
    print(f"Loading video: {input_path}")

    # Load video
    video = VideoFileClip(input_path)
    original_fps = video.fps

    print(f"Original size: {video.size[0]}x{video.size[1]}")
    print(f"Original FPS: {original_fps}")
    print(f"Duration: {video.duration:.2f}s")

    # Trim first 5 seconds and last 1 second
    total_trim = TRIM_START_SECONDS + TRIM_END_SECONDS
    if video.duration > total_trim:
        print(f"Trimming first {TRIM_START_SECONDS}s and last {TRIM_END_SECONDS}s...")
        video = video.subclipped(TRIM_START_SECONDS, video.duration - TRIM_END_SECONDS)
        print(f"New duration: {video.duration:.2f}s")
    else:
        print(f"Warning: Video is shorter than {total_trim}s, not trimming")

    # Get audio after trim
    original_audio = video.audio

    # Resize to TikTok format
    print("Resizing to 1080x1920...")
    video = resize_video_to_tiktok(video)

    # Create banner
    print(f"Creating banner with caption: {caption[:50]}...")
    banner_array = create_banner_image(caption)
    banner_clip = ImageClip(banner_array).with_duration(video.duration)

    # Position banner at top (0, 0)
    banner_clip = banner_clip.with_position((0, 0))

    # Position video with 20px offset from top
    video = video.with_position((0, VIDEO_TOP_OFFSET))

    # Create black background
    background = ColorClip(size=(OUTPUT_WIDTH, OUTPUT_HEIGHT), color=(0, 0, 0)).with_duration(video.duration)

    # Composite: background, then video (offset), then banner on top
    print("Compositing video with banner...")
    final = CompositeVideoClip([background, video, banner_clip], size=(OUTPUT_WIDTH, OUTPUT_HEIGHT))

    # Preserve audio
    if original_audio is not None:
        final = final.with_audio(original_audio)

    # Export
    print(f"Exporting to: {output_path}")
    final.write_videofile(
        output_path,
        fps=original_fps,
        codec="libx264",
        audio_codec="aac",
        preset="medium",
        threads=4,
    )

    # Cleanup
    video.close()
    final.close()

    print(f"Done! Output saved to: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Add a white banner with caption text to a video (TikTok 1080x1920 output)"
    )
    parser.add_argument(
        "--input", "-i",
        required=True,
        help="Input video file path"
    )
    parser.add_argument(
        "--output", "-o",
        required=True,
        help="Output video file path"
    )
    parser.add_argument(
        "--caption", "-c",
        required=True,
        help="Caption text to display in the banner"
    )

    args = parser.parse_args()

    # Validate input file
    if not os.path.isfile(args.input):
        print(f"Error: Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    # Validate font file
    if not FONT_PATH.is_file():
        print(f"Warning: Font not found at {FONT_PATH}, using fallback font", file=sys.stderr)

    # Process video
    add_banner_to_video(args.input, args.output, args.caption)


if __name__ == "__main__":
    main()
