"""
Storage backend abstraction for the Content Engine.

Provides:
- StorageBackend: Abstract base class
- LocalStorageBackend: Saves to local filesystem, serves via static mount
- (Future) S3StorageBackend: Upload to S3/R2 object storage

Usage:
    backend = LocalStorageBackend(config)
    save_result = backend.save(image, batch_id, filename)
    url = save_result.url
"""

import abc
import uuid
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Optional

from PIL import Image

from .config import Config, get_config


@dataclass
class SaveResult:
    """Result of saving an image."""
    filename: str
    local_path: Path
    url: str
    batch_id: str


class StorageBackend(abc.ABC):
    """Abstract base class for storage backends."""

    @abc.abstractmethod
    def save(
        self,
        image: Image.Image,
        batch_id: str,
        filename: str,
    ) -> SaveResult:
        """
        Save an image and return its metadata.

        Args:
            image: PIL Image to save
            batch_id: Batch identifier for grouping
            filename: Filename for the image

        Returns:
            SaveResult with path and URL info
        """
        pass

    @abc.abstractmethod
    def get_batch_dir(self, batch_id: str) -> Path:
        """Get the directory path for a batch."""
        pass

    @staticmethod
    def generate_batch_id() -> str:
        """Generate a unique batch ID."""
        return str(uuid.uuid4())[:8]


class LocalStorageBackend(StorageBackend):
    """
    Local filesystem storage backend.

    Saves images to:
        {output_dir}/{date}/{batch_id}/{filename}

    URLs are constructed as:
        {public_base_url}/output/{date}/{batch_id}/{filename}

    For local dev, FastAPI mounts ./output as /output static directory.
    For prod, PUBLIC_BASE_URL can point to a CDN or the same server.
    """

    def __init__(self, config: Optional[Config] = None):
        """
        Initialize local storage backend.

        Args:
            config: Configuration instance. Uses global config if not provided.
        """
        self.config = config or get_config()

    def get_batch_dir(self, batch_id: str) -> Path:
        """
        Get the directory path for a batch.

        Structure: {output_dir}/{date}/{batch_id}/
        """
        today = date.today().isoformat()
        return self.config.output_dir / today / batch_id

    def save(
        self,
        image: Image.Image,
        batch_id: str,
        filename: str,
    ) -> SaveResult:
        """
        Save an image to local filesystem.

        Args:
            image: PIL Image to save (should be RGB or RGBA)
            batch_id: Batch identifier
            filename: Filename (e.g., "neg_1.png")

        Returns:
            SaveResult with local path and public URL
        """
        batch_dir = self.get_batch_dir(batch_id)
        batch_dir.mkdir(parents=True, exist_ok=True)

        local_path = batch_dir / filename

        # Ensure RGB for PNG save
        if image.mode == "RGBA":
            image = image.convert("RGB")
        image.save(local_path, format="PNG")

        # Construct public URL
        # Path relative to output_dir for URL construction
        today = date.today().isoformat()
        url = f"{self.config.public_base_url}/output/{today}/{batch_id}/{filename}"

        return SaveResult(
            filename=filename,
            local_path=local_path,
            url=url,
            batch_id=batch_id,
        )


class S3StorageBackend(StorageBackend):
    """
    S3/R2 object storage backend (stub for future implementation).

    To implement:
    1. Add boto3 to requirements
    2. Add S3_BUCKET, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY to env
    3. Implement save() to upload to S3
    4. Return CloudFront/R2 public URL
    """

    def __init__(self, config: Optional[Config] = None):
        self.config = config or get_config()
        raise NotImplementedError(
            "S3StorageBackend is not yet implemented. "
            "Use LocalStorageBackend for now."
        )

    def get_batch_dir(self, batch_id: str) -> Path:
        today = date.today().isoformat()
        return Path(f"{today}/{batch_id}")

    def save(
        self,
        image: Image.Image,
        batch_id: str,
        filename: str,
    ) -> SaveResult:
        # Future: Upload to S3 using boto3
        raise NotImplementedError("S3StorageBackend.save() not implemented")
