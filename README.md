# Image Downloader

A Python script that downloads images from direct image URLs or from all images on a web page. Standard library only, so no `pip install` is needed (Python 3.8+).

## Usage

```bash
python download_images.py https://example.com/photo.jpg
python download_images.py https://example.com/gallery -o pics --min-bytes 5000
python download_images.py -l urls.txt
```

| Option | Description |
|---|---|
| `urls` | One or more image or page URLs |
| `-l`, `--list-file` | Text file with one URL per line (`#` lines ignored) |
| `-o`, `--out-dir` | Output folder (default `images`) |
| `--min-bytes` | Skip files smaller than this size |
| `--timeout` | Per-request timeout in seconds (default 30) |

## Notes

- Finds images in `<img src>`, `data-src`, `srcset` and `og:image`.
- Pages that load images with JavaScript are not supported.
- Requests to `sellercentral.amazon.com` are blocked by policy.
