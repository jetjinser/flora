#! /bin/sh
# Fetch the Noto CJK SC source fonts that (cjk-fonts) subsets from.
# Noto CJK is SIL OFL 1.1; the license files ship alongside the built
# webfonts in fonts/.
set -e
cd "$(dirname "$0")"
mkdir -p fonts-src
base=https://raw.githubusercontent.com/notofonts/noto-cjk/main
for path in \
  Serif/OTF/SimplifiedChinese/NotoSerifCJKsc-Light.otf \
  Serif/OTF/SimplifiedChinese/NotoSerifCJKsc-Regular.otf \
  Serif/OTF/SimplifiedChinese/NotoSerifCJKsc-Bold.otf \
  Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf
do
  name=$(basename "$path")
  if [ -f "fonts-src/$name" ]; then
    echo "have $name"
  else
    echo "fetching $path"
    curl --fail --silent --location --show-error \
      -o "fonts-src/$name.part" "$base/$path"
    mv "fonts-src/$name.part" "fonts-src/$name"
  fi
done
