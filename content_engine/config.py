"""
Configuration module for the Content Engine.

Handles:
- Environment variable loading
- Path configuration (NEG_ROOT, POS_ROOT, OUTPUT_DIR)
- Layout settings (SETTINGS dict)
- Public URL configuration for API responses
"""

import os
from pathlib import Path
from typing import Dict, List, Any, Optional
from functools import lru_cache

# Try to load .env file if python-dotenv is available
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass


class ConfigError(Exception):
    """Raised when configuration is invalid."""
    pass


class Config:
    """
    Centralized configuration for the content engine.

    All paths and settings are configurable via environment variables
    with sensible defaults for local development.
    """

    # Layout settings - defines how collages are composed
    SETTINGS: Dict[str, Dict[str, Any]] = {
        "default": {
            "neg_subfolders": ["alc", "badfood", "bumlife", "dashboard"],
            "pos_subfolders": ["atheletic", "dashboard", "food", "money"],
            "canvas_size": (1080, 1080),
            "image_size": (540, 540),
            "layout": "2x2"
        },
        "3s": {
            "neg_subfolders": ["alc", "bumlife", "dashboard_portrait"],
            "pos_subfolders": ["atheletic", "food", "dashboard_portrait"],
            "canvas_size": (1080, 1080),
            "image_size": (540, 540),
            "layout": "3s_split"
        }
    }

    # Image generation constants
    OVERLAY_OPACITY: int = int(255 * 0.44)
    FONT_SIZE: int = 32
    VALID_IMAGE_EXTENSIONS: tuple = (".jpg", ".jpeg", ".png")

    def __init__(
        self,
        base_dir: Optional[Path] = None,
        neg_root: Optional[Path] = None,
        pos_root: Optional[Path] = None,
        output_dir: Optional[Path] = None,
        font_path: Optional[Path] = None,
        public_base_url: Optional[str] = None,
    ):
        """
        Initialize configuration.

        Args:
            base_dir: Base directory for relative paths. Defaults to current working directory.
            neg_root: Path to negatives folder. Overrides NEG_ROOT env var.
            pos_root: Path to positives folder. Overrides POS_ROOT env var.
            output_dir: Path to output folder. Overrides OUTPUT_DIR env var.
            font_path: Path to font file. Overrides FONT_PATH env var.
            public_base_url: Public URL base for generated image URLs. Overrides PUBLIC_BASE_URL env var.
        """
        self.base_dir = base_dir or Path(os.getcwd())

        # Resolve paths from args, env vars, or defaults
        self.neg_root = self._resolve_path(
            neg_root,
            os.environ.get("NEG_ROOT"),
            self.base_dir / "negatives"
        )

        self.pos_root = self._resolve_path(
            pos_root,
            os.environ.get("POS_ROOT"),
            self.base_dir / "positives"
        )

        self.output_dir = self._resolve_path(
            output_dir,
            os.environ.get("OUTPUT_DIR"),
            self.base_dir / "output"
        )

        self.font_path = self._resolve_path(
            font_path,
            os.environ.get("FONT_PATH"),
            self.base_dir / "fonts" / "tiktok-sans-scm.ttf"
        )

        self.library_path = self._resolve_path(
            None,
            os.environ.get("LIBRARY_PATH"),
            self.base_dir / "library"
        )

        # Public URL for API responses
        self.public_base_url = (
            public_base_url
            or os.environ.get("PUBLIC_BASE_URL")
            or "http://localhost:8000"
        )
        # Ensure no trailing slash
        self.public_base_url = self.public_base_url.rstrip("/")

    def _resolve_path(
        self,
        explicit: Optional[Path],
        env_value: Optional[str],
        default: Path
    ) -> Path:
        """Resolve a path from explicit value, env var, or default."""
        if explicit is not None:
            return Path(explicit)
        if env_value is not None:
            return Path(env_value)
        return default

    def get_root_for_type(self, kind: str) -> Path:
        """
        Get the root folder path for a given type.

        Args:
            kind: Either "neg" or "pos"

        Returns:
            Path to the root folder for that type

        Raises:
            ValueError: If kind is not "neg" or "pos"
        """
        if kind == "neg":
            return self.neg_root
        elif kind == "pos":
            return self.pos_root
        else:
            raise ValueError(f"Invalid kind '{kind}'. Must be 'neg' or 'pos'.")

    def get_setting(self, setting_name: str) -> Dict[str, Any]:
        """
        Get a layout setting configuration.

        Args:
            setting_name: Name of the setting (e.g., "default", "3s")

        Returns:
            Setting configuration dict

        Raises:
            ConfigError: If setting name is not found
        """
        if setting_name not in self.SETTINGS:
            available = ", ".join(self.SETTINGS.keys())
            raise ConfigError(
                f"Unknown setting '{setting_name}'. Available: {available}"
            )
        return self.SETTINGS[setting_name]

    def get_subfolders(self, kind: str, setting_name: str) -> List[str]:
        """
        Get the list of subfolders for a given type and setting.

        Args:
            kind: Either "neg" or "pos"
            setting_name: Name of the setting

        Returns:
            List of subfolder names
        """
        setting = self.get_setting(setting_name)
        key = "neg_subfolders" if kind == "neg" else "pos_subfolders"
        return setting[key]

    def validate(self) -> None:
        """
        Validate that all required paths exist.

        Raises:
            ConfigError: If any required path is missing
        """
        errors = []

        if not self.neg_root.is_dir():
            errors.append(f"Negatives folder not found: {self.neg_root}")

        if not self.pos_root.is_dir():
            errors.append(f"Positives folder not found: {self.pos_root}")

        if not self.font_path.is_file():
            errors.append(f"Font file not found: {self.font_path}")

        if errors:
            raise ConfigError("\n".join(errors))

    def ensure_output_dir(self) -> None:
        """Create output directory if it doesn't exist."""
        self.output_dir.mkdir(parents=True, exist_ok=True)

    @classmethod
    def available_settings(cls) -> List[str]:
        """Return list of available setting names."""
        return list(cls.SETTINGS.keys())


# Global config instance (lazy-loaded)
_config: Optional[Config] = None


def get_config() -> Config:
    """
    Get the global Config instance.

    Creates a new instance on first call, reuses it thereafter.
    For testing, you can set _config directly or use init_config().
    """
    global _config
    if _config is None:
        _config = Config()
    return _config


def init_config(**kwargs) -> Config:
    """
    Initialize and return a new global Config instance.

    Use this to override the default configuration.
    """
    global _config
    _config = Config(**kwargs)
    return _config
