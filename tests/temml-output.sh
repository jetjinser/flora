#!/bin/sh
# SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

inline=build/math-0003.html
display=build/blazek2005-10-3-5.html

if ! grep -Fq 'class="math-inline"><math xmlns="http://www.w3.org/1998/Math/MathML"' "$inline"; then
  echo "Temml output check: inline TeX was not rendered as MathML in $inline" >&2
  exit 1
fi

if ! grep -Fq 'class="math-display" id="eq-10-32"><math xmlns="http://www.w3.org/1998/Math/MathML"' "$display"; then
  echo "Temml output check: display TeX or its authored ID is missing in $display" >&2
  exit 1
fi

if ! grep -Fq 'display="block" class="tml-display"' "$display"; then
  echo "Temml output check: display TeX lost its block presentation" >&2
  exit 1
fi

if grep -Fq 'MathJax' "$inline"; then
  echo "Temml output check: legacy MathJax output remains in $inline" >&2
  exit 1
fi

echo "Temml output check: inline and display MathML, display mode, and equation ID verified"
