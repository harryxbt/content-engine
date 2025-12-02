# new_files_crop_only.py

import os
import re
from PIL import Image

TARGET_SIZE = (540, 540)
PORTRAIT_SIZE = (540, 1080)

def crop_center(img):
    width, height = img.size
    new_edge = min(width, height)
    left = (width - new_edge) // 2
    top = (height - new_edge) // 2
    return img.crop((left, top, left + new_edge, top + new_edge)).resize(TARGET_SIZE, Image.LANCZOS)

def crop_portrait(img):
    width, height = img.size
    target_ratio = PORTRAIT_SIZE[0] / PORTRAIT_SIZE[1]  # 0.5
    current_ratio = width / height
    
    if current_ratio > target_ratio:
        # Too wide, crop width
        new_width = int(height * target_ratio)
        left = (width - new_width) // 2
        img = img.crop((left, 0, left + new_width, height))
    else:
        # Too tall, crop height
        new_height = int(width / target_ratio)
        top = (height - new_height) // 2
        img = img.crop((0, top, width, top + new_height))
    
    return img.resize(PORTRAIT_SIZE, Image.LANCZOS)

def process_new_images(root_folder, prefix):
    for subfolder in os.listdir(root_folder):
        sub_path = os.path.join(root_folder, subfolder)
        if not os.path.isdir(sub_path):
            continue

        pattern = re.compile(rf"{prefix}_{subfolder}_(\d+)\.png")
        existing = [int(m.group(1)) for f in os.listdir(sub_path)
                    if (m := pattern.match(f))]
        start_index = max(existing, default=0) + 1

        files = sorted(f for f in os.listdir(sub_path)
                       if f.lower().endswith((".jpg", ".jpeg", ".png"))
                       and not pattern.match(f))

        for f in files:
            original_path = os.path.join(sub_path, f)
            new_name = f"{prefix}_{subfolder}_{start_index}.png"
            new_path = os.path.join(sub_path, new_name)

            try:
                with Image.open(original_path) as img:
                    img = img.convert("RGB")
                    # Use portrait crop for dashboard_portrait folders, regular crop for others
                    if subfolder == "dashboard_portrait":
                        cropped = crop_portrait(img)
                    else:
                        cropped = crop_center(img)
                    cropped.save(new_path, "PNG")
                if original_path != new_path:
                    os.remove(original_path)
                print(f"🆕 Cropped: {f} → {new_name}")
                start_index += 1
            except Exception as e:
                print(f"❌ Error: {f} → {e}")

# Run from inside followboost/
process_new_images("negatives", "neg")
process_new_images("positives", "pos")