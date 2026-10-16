#! /bin/sh
# Regenerate the blazek2005 figures under assets/blazek2005/ from the
# scanned source PDF. The figures are not checked in; the crop manifest
# docs/blazek2005-figures.tsv (name, PDF page, x, y, w, h at 200 dpi)
# locates each one, and the crops reproduce the original figures pixel
# for pixel. Needs pdftoppm and magick, e.g.:
#
#   nix shell nixpkgs#poppler-utils nixpkgs#imagemagick \
#     -c ./regenerate-figures.sh
set -e
cd "$(dirname "$0")"
pdf="materials/books/Computational Fluid Dynamics Principles and Appl.pdf"
manifest="docs/blazek2005-figures.tsv"
out="assets/blazek2005"
cache="${TMPDIR:-/tmp}/flora-figure-pages"
[ -f "$pdf" ] || { echo "missing $pdf" >&2; exit 1; }
mkdir -p "$cache" "$out"
IFS="$(printf '\t')"
while read -r name page x y w h; do
  case $name in ''|\#*) continue ;; esac
  p=$(printf %03d "$page")
  page_png="$cache/p$p.png"
  if [ ! -f "$page_png" ]; then
    pdftoppm -png -r 200 -f "$page" -l "$page" "$pdf" "$cache/tmp$p"
    mv "$cache/tmp$p-$p.png" "$page_png"
  fi
  magick "$page_png" -crop "${w}x${h}+${x}+${y}" +repage "$out/$name"
done < "$manifest"
echo "regenerated $(grep -c -v '^#' "$manifest") figures into $out"
