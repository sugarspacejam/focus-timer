from pathlib import Path
import argparse
import cv2
import numpy as np
from PIL import Image

SUPPORTED_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}
REGION_WIDTH_RATIO = 0.14
REGION_HEIGHT_RATIO = 0.14
RIGHT_MARGIN_RATIO = 0.002
BOTTOM_MARGIN_RATIO = 0.002
MIN_COMPONENT_AREA_RATIO = 0.00002
MAX_COMPONENT_AREA_RATIO = 0.0025
PERCENTILE_THRESHOLD = 99.7
THRESHOLD_MARGIN = 8
INPAINT_RADIUS = 5


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_path")
    parser.add_argument("--output-dir")
    parser.add_argument("--suffix", default="-clean")
    return parser.parse_args()


def validate_input_path(input_path: Path) -> None:
    if not input_path.exists():
        raise FileNotFoundError(f"Input path does not exist: {input_path}")


def resolve_output_dir(input_path: Path, output_dir_argument: str | None) -> Path:
    if output_dir_argument:
        output_dir = Path(output_dir_argument)
        output_dir.mkdir(parents=True, exist_ok=True)
        return output_dir

    if input_path.is_dir():
        output_dir = input_path / "cleaned"
        output_dir.mkdir(parents=True, exist_ok=True)
        return output_dir

    return input_path.parent


def collect_image_paths(input_path: Path) -> list[Path]:
    if input_path.is_file():
        if input_path.suffix.lower() not in SUPPORTED_SUFFIXES:
            raise ValueError(f"Unsupported image format: {input_path.suffix}")
        return [input_path]

    image_paths = sorted(
        path for path in input_path.iterdir() if path.is_file() and path.suffix.lower() in SUPPORTED_SUFFIXES
    )
    if not image_paths:
        raise ValueError(f"No supported images found in: {input_path}")
    return image_paths


def build_region_box(image_width: int, image_height: int) -> tuple[int, int, int, int]:
    region_width = max(32, round(image_width * REGION_WIDTH_RATIO))
    region_height = max(32, round(image_height * REGION_HEIGHT_RATIO))
    x2 = image_width - max(1, round(image_width * RIGHT_MARGIN_RATIO))
    y2 = image_height - max(1, round(image_height * BOTTOM_MARGIN_RATIO))
    x1 = max(0, x2 - region_width)
    y1 = max(0, y2 - region_height)
    return (x1, y1, x2, y2)


def build_watermark_mask(image_array_bgr: np.ndarray) -> np.ndarray:
    image_height, image_width = image_array_bgr.shape[:2]
    region_x1, region_y1, region_x2, region_y2 = build_region_box(image_width, image_height)
    region = image_array_bgr[region_y1:region_y2, region_x1:region_x2]
    region_gray = cv2.cvtColor(region, cv2.COLOR_BGR2GRAY)
    region_threshold = max(160, int(np.percentile(region_gray, PERCENTILE_THRESHOLD)) - THRESHOLD_MARGIN)
    _, bright_mask = cv2.threshold(region_gray, region_threshold, 255, cv2.THRESH_BINARY)
    component_count, labels, stats, centroids = cv2.connectedComponentsWithStats(bright_mask, connectivity=8)
    filtered_region_mask = np.zeros_like(bright_mask)
    minimum_component_area = max(6, round(image_width * image_height * MIN_COMPONENT_AREA_RATIO))
    maximum_component_area = max(minimum_component_area + 1, round(image_width * image_height * MAX_COMPONENT_AREA_RATIO))
    best_component_index: int | None = None
    best_component_score: float | None = None
    target_x = region.shape[1] - 1
    target_y = region.shape[0] - 1

    for component_index in range(1, component_count):
        component_area = stats[component_index, cv2.CC_STAT_AREA]
        if component_area < minimum_component_area:
            continue
        if component_area > maximum_component_area:
            continue
        centroid_x, centroid_y = centroids[component_index]
        distance_to_corner = ((target_x - centroid_x) ** 2 + (target_y - centroid_y) ** 2) ** 0.5
        component_score = distance_to_corner - component_area * 0.03
        if best_component_score is not None and component_score >= best_component_score:
            continue
        best_component_index = component_index
        best_component_score = component_score

    if best_component_index is not None:
        filtered_region_mask[labels == best_component_index] = 255

    kernel = np.ones((3, 3), dtype=np.uint8)
    filtered_region_mask = cv2.dilate(filtered_region_mask, kernel, iterations=2)
    full_mask = np.zeros((image_height, image_width), dtype=np.uint8)
    full_mask[region_y1:region_y2, region_x1:region_x2] = filtered_region_mask
    return full_mask


def clean_image(image_path: Path, output_path: Path) -> None:
    image = Image.open(image_path).convert("RGB")
    image_array_rgb = np.array(image)
    image_array_bgr = cv2.cvtColor(image_array_rgb, cv2.COLOR_RGB2BGR)
    watermark_mask = build_watermark_mask(image_array_bgr)
    cleaned_image_array_bgr = cv2.inpaint(image_array_bgr, watermark_mask, INPAINT_RADIUS, cv2.INPAINT_TELEA)
    cleaned_image_array_rgb = cv2.cvtColor(cleaned_image_array_bgr, cv2.COLOR_BGR2RGB)
    cleaned_image = Image.fromarray(cleaned_image_array_rgb)
    cleaned_image.save(output_path)


def build_output_path(image_path: Path, output_dir: Path, suffix: str) -> Path:
    return output_dir / f"{image_path.stem}{suffix}{image_path.suffix}"


def main() -> None:
    args = parse_args()
    input_path = Path(args.input_path)
    validate_input_path(input_path)
    output_dir = resolve_output_dir(input_path, args.output_dir)
    image_paths = collect_image_paths(input_path)

    for image_path in image_paths:
        output_path = build_output_path(image_path, output_dir, args.suffix)
        clean_image(image_path, output_path)
        print(f"Saved {output_path}")


if __name__ == "__main__":
    main()
