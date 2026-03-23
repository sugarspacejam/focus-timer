from pathlib import Path
from PIL import Image, ImageFilter

INPUT_PATH = Path("/Volumes/waffleman/chentoledano/Projects-new/focus-timer/screenshots/cropped-more-top/spearkingtou.png")
OUTPUT_PATH = Path("/Volumes/waffleman/chentoledano/Projects-new/focus-timer/screenshots/cropped-more-top/spearkingtou-clean.png")
PATCH_BOX = (404, 900, 496, 988)
SAMPLE_BOX = (300, 860, 392, 948)


def main() -> None:
    image = Image.open(INPUT_PATH).convert("RGBA")
    sample = image.crop(SAMPLE_BOX)
    patch_width = PATCH_BOX[2] - PATCH_BOX[0]
    patch_height = PATCH_BOX[3] - PATCH_BOX[1]
    patch = sample.resize((patch_width, patch_height), Image.Resampling.LANCZOS)
    patch = patch.filter(ImageFilter.GaussianBlur(radius=3.2))
    image.paste(patch, PATCH_BOX)
    image.save(OUTPUT_PATH)


if __name__ == "__main__":
    main()
