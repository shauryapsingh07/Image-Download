# Image Downloader

A PowerShell script that downloads images from direct image URLs or from all images on a web page. No dependencies; works with Windows PowerShell 5.1+.

## Usage

```powershell
.\Download-Images.ps1 -Url https://example.com/photo.jpg
.\Download-Images.ps1 -Url https://example.com/gallery -OutDir .\pics -MinBytes 5000
.\Download-Images.ps1 -ListFile urls.txt
```

| Parameter | Description |
|---|---|
| `-Url` | One or more image or page URLs |
| `-ListFile` | Text file with one URL per line (`#` lines ignored) |
| `-OutDir` | Output folder (default `.\images`) |
| `-MinBytes` | Skip files smaller than this size |
| `-TimeoutSec` | Per-request timeout (default 30) |

## Notes

- Finds images in `<img src>`, `data-src`, `srcset` and `og:image`.
- Pages that load images with JavaScript are not supported.
- Requests to `sellercentral.amazon.com` are blocked by policy.
