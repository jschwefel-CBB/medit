#!/bin/zsh
# Compose Mac App Store screenshots (1280x800, 16:10) from the captured app shots
# in docs/images/. Requires ImageMagick (`magick`). Re-run after updating sources.
set -e
cd "$(dirname "$0")/../.."
SRC=docs/images
OUT=docs/app-store/screenshots
FONT="/System/Library/Fonts/Helvetica.ttc"
mkdir -p "$OUT"
compose() {
  magick -size 1280x800 "xc:#1b1d22" \
    \( "$SRC/$1" -resize "1120x620>" -bordercolor "#000000" -border 1 \) \
    -gravity center -geometry +0+44 -composite \
    -gravity north -font "$FONT" -pointsize 36 -fill "#ececef" -annotate +0+30 "$3" \
    "$OUT/$2"
  echo "  → $2"
}
compose hero.png             01-editor.png   "A native editor with syntax highlighting"
compose markdown-preview.png 02-markdown.png "Live, native Markdown preview"
compose block-edit.png       03-block.png    "Column (block) editing"
compose find-in-tabs.png     04-find.png     "Find across every open tab"
compose settings.png         05-settings.png "Simple, thorough preferences"
echo "Done. App Store screenshots in $OUT (1280x800)."
