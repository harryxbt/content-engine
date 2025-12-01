"""
Content Engine - TikTok-style collage generator.

Package structure:
    content_engine/
        __init__.py         - Package exports
        config.py           - Configuration, paths, settings
        generator.py        - Pure collage generation logic
        storage.py          - Storage backend abstraction (local/S3)
    api/
        __init__.py
        main.py             - FastAPI application
"""

from .config import Config, get_config
from .generator import generate_collage, generate_batch
from .storage import LocalStorageBackend, StorageBackend
from .video_generator import generate_video, VideoNotFoundError

__all__ = [
    "Config",
    "get_config",
    "generate_collage",
    "generate_batch",
    "generate_video",
    "LocalStorageBackend",
    "StorageBackend",
    "VideoNotFoundError",
]
