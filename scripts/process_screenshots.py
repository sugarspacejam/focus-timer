#!/usr/bin/env python3
from PIL import Image
import os

# Target dimensions for App Store (iPhone 14 Pro Max)
TARGET_WIDTH = 1242
TARGET_HEIGHT = 2688

# Crop amount to remove status bar/island
CROP_TOP = 120

screenshot_dir = "/Volumes/waffleman/chentoledano/Projects-new/focus-timer/screenshots/done in 5 screenshots"

for filename in os.listdir(screenshot_dir):
    if filename.endswith('.png'):
        filepath = os.path.join(screenshot_dir, filename)
        print(f"Processing {filename}...")
        
        img = Image.open(filepath)
        
        # Crop 120px from top
        width, height = img.size
        cropped = img.crop((0, CROP_TOP, width, height))
        
        # Resize to target dimensions
        resized = cropped.resize((TARGET_WIDTH, TARGET_HEIGHT), Image.Resampling.LANCZOS)
        
        # Remove alpha channel (Apple rejects RGBA)
        if resized.mode == 'RGBA':
            rgb_image = Image.new('RGB', resized.size, (255, 255, 255))
            rgb_image.paste(resized, mask=resized.split()[3])
            resized = rgb_image
        
        # Save back to same file
        resized.save(filepath, 'PNG')
        print(f"  Cropped to {width}x{height-CROP_TOP}, resized to {TARGET_WIDTH}x{TARGET_HEIGHT}")

print("Done!")
