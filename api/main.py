"""
Content Engine API - FastAPI application for TikTok-style collage generation.

=============================================================================
HOW TO RUN
=============================================================================

Local Development:
    uvicorn api.main:app --reload --host 0.0.0.0 --port 8000

Production:
    uvicorn api.main:app --host 0.0.0.0 --port 8000 --workers 4

With Gunicorn (recommended for prod):
    gunicorn api.main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000

Local CLI Test (without server):
    python -m api.main --local-test

=============================================================================
ENVIRONMENT VARIABLES
=============================================================================

PUBLIC_BASE_URL     - Base URL for generated image URLs (default: http://localhost:8000)
NEG_ROOT            - Path to negatives folder (default: ./negatives)
POS_ROOT            - Path to positives folder (default: ./positives)
OUTPUT_DIR          - Path to output folder (default: ./output)
FONT_PATH           - Path to font file (default: ./fonts/tiktok-sans-scm.ttf)

=============================================================================
API ENDPOINTS
=============================================================================

GET  /health    - Health check
POST /generate  - Generate collage batch

=============================================================================
EXAMPLE REQUESTS
=============================================================================

Health Check:
    curl http://localhost:8000/health

Generate Collages:
    curl -X POST http://localhost:8000/generate \\
      -H "Content-Type: application/json" \\
      -d '{
        "captions": [
          {"text": "the road to hell feels like heaven", "type": "neg"},
          {"text": "the road to heaven feels like hell", "type": "pos"}
        ],
        "setting": "3s"
      }'

With custom batch_id:
    curl -X POST http://localhost:8000/generate \\
      -H "Content-Type: application/json" \\
      -d '{
        "captions": [
          {"text": "keep scrolling bro...", "type": "neg"},
          {"text": "this fyp aint for everyone", "type": "pos"}
        ],
        "setting": "default",
        "batch_id": "my-custom-batch"
      }'

=============================================================================
"""

import argparse
import logging
import sys
import traceback
from contextlib import asynccontextmanager
from pathlib import Path
from typing import List, Literal, Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, field_validator

# Add parent directory to path for imports when running directly
sys.path.insert(0, str(Path(__file__).parent.parent))

from content_engine.config import Config, get_config, init_config, ConfigError
from content_engine.generator import (
    generate_batch,
    generate_batch_local,
    NoImagesError,
)
from content_engine.storage import LocalStorageBackend

# =============================================================================
# Logging Configuration
# =============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("content_engine.api")


# =============================================================================
# Pydantic Models
# =============================================================================

class CaptionItem(BaseModel):
    """A single caption entry for collage generation."""
    text: str = Field(..., description="Caption text to display on the collage")
    type: Literal["neg", "pos"] = Field(
        ..., description="Type of collage: 'neg' for negative, 'pos' for positive"
    )


class GenerateRequest(BaseModel):
    """Request body for /generate endpoint."""
    captions: List[CaptionItem] = Field(
        ...,
        min_length=1,
        description="List of captions to generate collages for"
    )
    setting: str = Field(
        default="default",
        description="Layout setting name (e.g., 'default', '3s')"
    )
    batch_id: Optional[str] = Field(
        default=None,
        description="Optional custom batch ID for filenames. Auto-generated if not provided."
    )

    @field_validator("setting")
    @classmethod
    def validate_setting(cls, v: str) -> str:
        available = Config.available_settings()
        if v not in available:
            raise ValueError(
                f"Unknown setting '{v}'. Available: {', '.join(available)}"
            )
        return v


class GeneratedImage(BaseModel):
    """Information about a generated image."""
    caption: str
    type: Literal["neg", "pos"]
    filename: str
    url: str


class GenerateResponse(BaseModel):
    """Response body for /generate endpoint."""
    batch_id: str
    count: int
    images: List[GeneratedImage]


class HealthResponse(BaseModel):
    """Response body for /health endpoint."""
    status: str


class ErrorResponse(BaseModel):
    """Error response body."""
    error: str
    detail: str


# =============================================================================
# Lifespan - Startup/Shutdown Events
# =============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize configuration and mount static files on startup."""
    config = get_config()

    # Validate configuration
    try:
        config.validate()
        logger.info("Configuration validated successfully")
    except ConfigError as e:
        logger.error(f"Configuration error: {e}")
        # Don't fail startup - allow /health to report issues

    # Ensure output directory exists
    config.ensure_output_dir()

    # Mount output directory as static files
    # This makes generated images accessible at /output/...
    if config.output_dir.is_dir():
        app.mount(
            "/output",
            StaticFiles(directory=str(config.output_dir)),
            name="output"
        )
        logger.info(f"Mounted static files at /output -> {config.output_dir}")

    yield  # Application runs here

    # Shutdown logic (if needed) would go here
    logger.info("Shutting down Content Engine API")


# =============================================================================
# FastAPI Application
# =============================================================================

app = FastAPI(
    title="Content Engine API",
    description="TikTok-style collage generation API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)


# =============================================================================
# Exception Handlers
# =============================================================================

@app.exception_handler(NoImagesError)
async def no_images_error_handler(request: Request, exc: NoImagesError):
    """Handle missing images in folders."""
    logger.error(f"No images in folder: {exc.folder}")
    return JSONResponse(
        status_code=500,
        content={
            "error": "NO_IMAGES_IN_FOLDER",
            "detail": str(exc),
        }
    )


@app.exception_handler(ConfigError)
async def config_error_handler(request: Request, exc: ConfigError):
    """Handle configuration errors."""
    logger.error(f"Configuration error: {exc}")
    return JSONResponse(
        status_code=500,
        content={
            "error": "CONFIG_ERROR",
            "detail": str(exc),
        }
    )


# =============================================================================
# API Endpoints
# =============================================================================

@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    """
    Health check endpoint.

    Returns {"status": "ok"} when the service is running.
    """
    return {"status": "ok"}


@app.post(
    "/generate",
    response_model=GenerateResponse,
    responses={
        400: {"model": ErrorResponse, "description": "Invalid request"},
        500: {"model": ErrorResponse, "description": "Server error"},
    },
    tags=["Generation"],
)
async def generate_collages(request: GenerateRequest):
    """
    Generate collage images from captions.

    Creates one collage per caption entry. Each collage uses random images
    from the appropriate folders (negatives or positives) based on the type.

    The generated images are saved locally and accessible via the returned URLs.
    """
    config = get_config()

    logger.info(
        f"Generate request: count={len(request.captions)}, "
        f"setting={request.setting}, batch_id={request.batch_id}"
    )

    try:
        # Convert Pydantic models to dicts for generator
        captions_list = [
            {"text": c.text, "type": c.type}
            for c in request.captions
        ]

        # Create storage backend
        storage = LocalStorageBackend(config)

        # Determine batch_id
        batch_id = request.batch_id or storage.generate_batch_id()

        # Generate all collages
        results = generate_batch(
            captions=captions_list,
            setting_name=request.setting,
            batch_id=batch_id,
            config=config,
            storage=storage,
        )

        # Build response
        images = []
        for i, result in enumerate(results):
            caption_entry = request.captions[i]
            images.append(GeneratedImage(
                caption=caption_entry.text,
                type=caption_entry.type,
                filename=result.filename,
                url=result.url,
            ))

        response = GenerateResponse(
            batch_id=batch_id,
            count=len(images),
            images=images,
        )

        logger.info(f"Generated {len(images)} images for batch {batch_id}")

        return response

    except ValueError as e:
        logger.error(f"Validation error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

    except NoImagesError:
        # Re-raise to be handled by exception handler
        raise

    except Exception as e:
        logger.error(f"Unexpected error: {e}\n{traceback.format_exc()}")
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error: {str(e)}"
        )


# =============================================================================
# CLI Entry Point
# =============================================================================

def run_local_test():
    """Run a local test without starting the server."""
    print("=" * 60)
    print("Content Engine - Local Test Mode")
    print("=" * 60)

    # Initialize config
    config = init_config(
        base_dir=Path(__file__).parent.parent,
    )

    print(f"NEG_ROOT: {config.neg_root}")
    print(f"POS_ROOT: {config.pos_root}")
    print(f"OUTPUT_DIR: {config.output_dir}")
    print(f"FONT_PATH: {config.font_path}")
    print()

    # Validate configuration
    try:
        config.validate()
        print("Configuration: OK")
    except ConfigError as e:
        print(f"Configuration Error: {e}")
        sys.exit(1)

    # Test captions
    test_captions = [
        {"text": "the road to hell feels like heaven", "type": "neg"},
        {"text": "the road to heaven feels like hell", "type": "pos"},
        {"text": "keep scrolling bro...", "type": "neg"},
        {"text": "this fyp aint for everyone", "type": "pos"},
    ]

    print()
    print(f"Generating {len(test_captions)} test collages...")
    print()

    # Generate using local batch mode
    try:
        paths = generate_batch_local(
            captions=test_captions,
            setting_name="3s",
            config=config,
        )

        print()
        print("=" * 60)
        print("Generated files:")
        print("=" * 60)
        for path in paths:
            print(f"  {path}")

    except NoImagesError as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Content Engine API")
    parser.add_argument(
        "--local-test",
        action="store_true",
        help="Run local test without starting server"
    )

    args = parser.parse_args()

    if args.local_test:
        run_local_test()
    else:
        # Print usage hint
        print("Usage:")
        print("  Start server: uvicorn api.main:app --reload")
        print("  Local test:   python -m api.main --local-test")
