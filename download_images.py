#!/usr/bin/env python3
"""Download images from direct image URLs or from all <img> tags on web pages.

Examples:
    python download_images.py https://example.com/photo.jpg
    python download_images.py https://example.com/gallery -o pics --min-bytes 5000
    python download_images.py -l urls.txt
"""
import argparse
import html
import os
import re
import sys
import urllib.request
from urllib.parse import urljoin, urlparse

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ImageDownloader/1.0"
BLOCKED_HOSTS = ("sellercentral.amazon.com",)
EXT_BY_TYPE = {
    "image/jpeg": ".jpg", "image/png": ".png", "image/gif": ".gif",
    "image/webp": ".webp", "image/svg+xml": ".svg", "image/bmp": ".bmp",
    "image/avif": ".avif", "image/x-icon": ".ico",
}
IMG_PATTERNS = (
    r'<img\b[^>]*?\bsrc\s*=\s*["\']([^"\']+)["\']',
    r'<img\b[^>]*?\bdata-src\s*=\s*["\']([^"\']+)["\']',
    r'<meta\b[^>]*?property\s*=\s*["\']og:image["\'][^>]*?content\s*=\s*["\']([^"\']+)["\']',
)
SRCSET_PATTERN = r'\bsrcset\s*=\s*["\']([^"\']+)["\']'


def is_blocked(url):
    host = (urlparse(url).hostname or "").lower()
    return any(host == b or host.endswith("." + b) for b in BLOCKED_HOSTS)


def fetch(url, timeout):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read(), resp.headers.get("Content-Type", "")


def page_images(page_html, base_url):
    found = []
    for pattern in IMG_PATTERNS:
        found += re.findall(pattern, page_html, re.IGNORECASE)
    # srcset: take the last (usually largest) candidate
    for value in re.findall(SRCSET_PATTERN, page_html, re.IGNORECASE):
        last = value.split(",")[-1].strip().split()
        if last:
            found.append(last[0])
    urls = []
    for raw in found:
        if raw.startswith("data:"):
            continue
        absolute = urljoin(base_url, html.unescape(raw))
        if absolute not in urls:
            urls.append(absolute)
    return urls


def unique_path(out_dir, url, content_type):
    name = os.path.basename(urlparse(url).path) or "image"
    name = re.sub(r"[^\w.\-]", "_", name)
    stem, ext = os.path.splitext(name)
    if not ext:
        ext = EXT_BY_TYPE.get(content_type.split(";")[0].strip().lower(), "")
    path = os.path.join(out_dir, stem + ext)
    i = 1
    while os.path.exists(path):
        path = os.path.join(out_dir, f"{stem}_{i}{ext}")
        i += 1
    return path


def save_image(url, data, content_type, args):
    if not content_type.lower().startswith("image/"):
        print(f"Skipped (not an image: {content_type}): {url}", file=sys.stderr)
        return False
    if len(data) < args.min_bytes:
        print(f"Skipped (under {args.min_bytes} bytes): {url}", file=sys.stderr)
        return False
    path = unique_path(args.out_dir, url, content_type)
    with open(path, "wb") as f:
        f.write(data)
    print(f"Saved {path} ({len(data)} bytes)")
    return True


def main():
    parser = argparse.ArgumentParser(description="Download images from URLs or web pages.")
    parser.add_argument("urls", nargs="*", help="image or page URLs")
    parser.add_argument("-l", "--list-file", help="text file with one URL per line")
    parser.add_argument("-o", "--out-dir", default="images", help="output folder (default: images)")
    parser.add_argument("--min-bytes", type=int, default=0, help="skip files smaller than this")
    parser.add_argument("--timeout", type=int, default=30, help="per-request timeout in seconds")
    args = parser.parse_args()

    targets = list(args.urls)
    if args.list_file:
        with open(args.list_file, encoding="utf-8") as f:
            targets += [ln.strip() for ln in f if ln.strip() and not ln.startswith("#")]
    if not targets:
        parser.error("provide at least one URL or --list-file")

    os.makedirs(args.out_dir, exist_ok=True)
    saved = failed = 0

    for target in targets:
        try:
            if is_blocked(target):
                print(f"Blocked by policy: {target}", file=sys.stderr)
                failed += 1
                continue
            data, ctype = fetch(target, args.timeout)
            if ctype.lower().startswith("image/"):
                saved += save_image(target, data, ctype, args)
                continue
            images = page_images(data.decode("utf-8", errors="replace"), target)
            print(f"{target} -> {len(images)} image(s) found")
            for img in images:
                try:
                    if is_blocked(img):
                        continue
                    img_data, img_type = fetch(img, args.timeout)
                    if save_image(img, img_data, img_type, args):
                        saved += 1
                except Exception as e:
                    print(f"Failed {img}: {e}", file=sys.stderr)
                    failed += 1
        except Exception as e:
            print(f"Failed {target}: {e}", file=sys.stderr)
            failed += 1

    print(f"Done. Saved: {saved}, failed/skipped: {failed}. Output: {args.out_dir}")


if __name__ == "__main__":
    main()
