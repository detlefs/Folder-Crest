# Folder Crest website

Static one-pager, no build step. Run locally:

    cd Website && python3 -m http.server 8765   # http://localhost:8765

- Texts: each string exists twice in `index.html` (`lang="en"` / `lang="de"`).
- Images: `img/icons/*.png` are 512 px renders from the app; replace files, not CSS.
- GSAP is vendored in `vendor/` (no CDN, no third-party requests).
- Download links point to `.../releases/latest`; the repo URL is a placeholder (`detlefs/Folder-Crest`), search and replace before deployment.
