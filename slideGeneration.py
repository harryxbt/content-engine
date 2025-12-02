import os
import random
from PIL import Image, ImageDraw, ImageFont

# === CONFIG ===
NEG_SUBFOLDERS = ["alc", "badfood", "bumlife", "dashboard"]
POS_SUBFOLDERS = ["atheletic", "dashboard", "food", "money"]

NEG_ROOT = "./negatives"
POS_ROOT = "./positives"
OUTPUT_DIR = "./output"
FONT_PATH = ("./fonts/tiktok-sans-scm.ttf")  # Update path if needed

IMAGE_SIZE = (540, 540)
CANVAS_SIZE = (1080, 1080)
OVERLAY_OPACITY = int(255 * 0.44)
FONT_SIZE = 32

# Settings configurations
SETTINGS = {
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

# Choose setting here
CURRENT_SETTING = "3s"

captions_to_generate = [
    {"text": "the road to hell feels like heaven", "type": "neg"},
    {"text": "the road to heaven feels like hell", "type": "pos"},
    {"text": "your fyp now", "type": "neg"},
    {"text": "your fyp after following me", "type": "pos"},
    {"text": "keep scrolling bro...", "type": "neg"},
    {"text": "this fyp aint for everyone", "type": "pos"},
    {"text": "keep scrolling bro...", "type": "neg"},
    {"text": "this fyp aint for everyone", "type": "pos"},
    {"text": "when life is hard so you pull out this >", "type": "neg"},
    {"text": "...", "type": "pos"},
    {"text": "the problem", "type": "neg"},
    {"text": "the solution", "type": "pos"},
    {"text": "work til failure", "type": "neg"},
    {"text": "or be the failure", "type": "pos"},
    {"text": "your slowly realising...", "type": "neg"},
    {"text": "he was right all the time", "type": "pos"},
    {"text": "0% love", "type": "neg"},
    {"text": "100% discipline", "type": "pos"},
    {"text": "bro look at you", "type": "neg"},
    {"text": "your losing focus again", "type": "pos"},
    {"text": "your so boring", "type": "neg"},
    {"text": "nahh just different goals", "type": "pos"}
]

os.makedirs(OUTPUT_DIR, exist_ok=True)


# === HELPERS ===

def pick_random_image_from(folder):
    files = [f for f in os.listdir(folder) if f.lower().endswith((".jpg", ".png", ".jpeg"))]
    if not files:
        raise FileNotFoundError(f"No images found in {folder}")
    return os.path.join(folder, random.choice(files))


def build_collage(image_paths, caption, output_name, setting_config):
    canvas_size = setting_config["canvas_size"]
    image_size = setting_config["image_size"]
    layout = setting_config["layout"]
    
    canvas = Image.new("RGB", canvas_size)

    if layout == "3s_split":
        # 3s layout: 2 square images on left (540x540), 1 portrait on right (540x1080)
        for i, path in enumerate(image_paths):
            if i < 2:
                # First 2 images: left side, stacked vertically
                img = Image.open(path).resize((540, 540))
                x = 0
                y = i * 540
                canvas.paste(img, (x, y))
            else:
                # Third image: right side, full height portrait
                img = Image.open(path).resize((540, 1080))
                x = 540
                y = 0
                canvas.paste(img, (x, y))
    elif layout == "portrait":
        # Portrait layout: stack 3 images vertically (540x360 each in 540x1080 canvas)
        portrait_image_size = (540, 360)
        for i, path in enumerate(image_paths):
            img = Image.open(path).resize(portrait_image_size)
            x = 0
            y = i * 360
            canvas.paste(img, (x, y))
    else:
        # Default 2x2 layout
        for i, path in enumerate(image_paths):
            img = Image.open(path).resize(image_size)
            x = (i % 2) * image_size[0]
            y = (i // 2) * image_size[1]
            canvas.paste(img, (x, y))

    # Add semi-transparent black overlay
    overlay = Image.new("RGBA", canvas_size, (0, 0, 0, OVERLAY_OPACITY))
    canvas = canvas.convert("RGBA")
    canvas = Image.alpha_composite(canvas, overlay)

    # Add centered white caption text (no stroke)
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
    bbox = draw.textbbox((0, 0), caption, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]

    x = (canvas_size[0] - text_w) / 2
    y = (canvas_size[1] - text_h) / 2

    draw.text((x, y), caption, font=font, fill="white")

    # Save image as PNG
    out_path = output_name
    canvas.convert("RGB").save(out_path, format="PNG")
    print(f"✅ Saved: {out_path}")


# === MAIN LOGIC ===

# Get current setting configuration
current_config = SETTINGS[CURRENT_SETTING]

for i, entry in enumerate(captions_to_generate):
    folder_index = (i // 2) + 1
    folder = os.path.join(OUTPUT_DIR, f"img_{folder_index}")
    os.makedirs(folder, exist_ok=True)
    folder_root = NEG_ROOT if entry["type"] == "neg" else POS_ROOT
    subfolders = current_config["neg_subfolders"] if entry["type"] == "neg" else current_config["pos_subfolders"]
    image_paths = [pick_random_image_from(os.path.join(folder_root, sub)) for sub in subfolders]
    filename = os.path.join(folder, f"{entry['type']}_{i+1}.png")
    build_collage(image_paths, entry["text"], filename, current_config)
