#!/bin/sh
# SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Browser check for the link preview: it opens on focus, preserves nested links,
# removes other controls, and closes on Escape and focusout.

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build=${BUILD_DIR:-$root/build}

find_chromium() {
    if [ -n "${CHROMIUM:-}" ]; then
        printf '%s\n' "$CHROMIUM"
        return
    fi
    for command in chromium chromium-browser google-chrome; do
        if command -v "$command" >/dev/null 2>&1; then
            command -v "$command"
            return
        fi
    done
    for path in /gnu/store/*-chromium-*/bin/chromium \
                /gnu/store/*-ungoogled-chromium-*/bin/chromium; do
        if [ -x "$path" ]; then
            printf '%s\n' "$path"
            return
        fi
    done
    return 1
}

chromium=$(find_chromium) || {
    echo "preview-check: no Chromium found; set CHROMIUM=/path/to/chromium" >&2
    exit 1
}

for asset in theme.js forester.css flora.css i18n.css highlight.css; do
    if [ ! -f "$build/$asset" ]; then
        echo "preview-check: missing $build/$asset; run make build" >&2
        exit 1
    fi
done

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
cp "$build/theme.js" "$build/forester.css" "$build/flora.css" \
   "$build/i18n.css" "$build/highlight.css" "$temporary/"

cat > "$temporary/target.html" <<'TARGET'
<!doctype html>
<html lang="en">
<body>
<article>
<section class="forest-tree-block page-tree" id="tree-root-target"><details open><summary><h1 class="forest-tree-title">Target page</h1></summary><div class="forest-tree-content"><p>Page lead outside the anchor.</p><section class="forest-tree-block inline-subtree" id="target-section"><details open><summary><h2 class="forest-tree-title">Target section</h2></summary><div class="forest-tree-content"><p>Anchor-specific body.</p><a href="#">a link</a><button>a button</button></div></details></section></div></details></section>
</article>
</body>
</html>
TARGET

cat > "$temporary/probe.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<link rel="stylesheet" href="forester.css">
<link rel="stylesheet" href="flora.css">
<script src="theme.js"></script>
</head>
<body>
<a id="probe" href="$temporary/target.html#target-section">preview target</a>
<script>
(function () {
  window.addEventListener("load", function () {
    var link = document.getElementById("probe");
    var card;
    var state = { opened: false, hidden: false, focusable: -1, closed: false, blurClosed: false, title: "", body: "" };
    var target = '<!doctype html><html><body><article>' +
      '<section class="forest-tree-block page-tree" id="tree-root-target"><details open><summary><h1 class="forest-tree-title">Target page</h1></summary><div class="forest-tree-content"><p>Page lead outside the anchor.</p>' +
      '<section class="forest-tree-block inline-subtree" id="target-section"><details open><summary><h2 class="forest-tree-title">Target section</h2></summary><div class="forest-tree-content"><p>Anchor-specific body.</p><a href="#">a link</a><button>a button</button></div></details></section>' +
      '</div></details></section></article></body></html>';
    var nativeFetch = window.fetch.bind(window);

    // file:// pages cannot fetch sibling files in Chromium. Keep the real
    // preview code under test and provide the target document as a response.
    window.fetch = function (url, options) {
      if (url === link.href.split("#")[0]) {
        return Promise.resolve({
          ok: true,
          text: function () { return Promise.resolve(target); }
        });
      }
      return nativeFetch(url, options);
    };

    function snapshot() {
      card = document.querySelector(".link-preview");
      state.open = !!(card && card.classList.contains("open"));
      if (card) {
        state.hidden = card.getAttribute("aria-hidden") === "true";
        state.focusable = card.querySelectorAll("a,button,input,select,textarea,[tabindex]").length;
        state.title = card.querySelector(".link-preview-title").textContent;
        state.body = card.querySelector(".link-preview-body").textContent;
      }
    }

    function finish() {
      var pre = document.createElement("pre");
      pre.id = "preview-check";
      pre.textContent = JSON.stringify(state);
      document.body.appendChild(pre);
    }

    function waitForOpen(after) {
      var current = document.querySelector(".link-preview");
      if (current && current.classList.contains("open")) {
        after();
        return;
      }
      var observer = new MutationObserver(function () {
        var next = document.querySelector(".link-preview");
        if (next && next.classList.contains("open")) {
          observer.disconnect();
          after();
        }
      });
      observer.observe(document.body, {
        attributes: true,
        subtree: true,
        attributeFilter: ["class"]
      });
    }

    function openAndCheck(after) {
      link.dispatchEvent(new FocusEvent("focusin", {bubbles: true}));
      waitForOpen(function () {
        snapshot();
        after();
      });
    }

    openAndCheck(function () {
      state.opened = state.open;
      document.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true}));
      setTimeout(function () {
        snapshot();
        state.closed = !state.open;
        openAndCheck(function () {
          link.dispatchEvent(new FocusEvent("focusout", {
            bubbles: true,
            relatedTarget: document.body
          }));
          setTimeout(function () {
            snapshot();
            state.blurClosed = !state.open;
            finish();
          }, 300);
        });
      }, 250);
    });
  });
})();
</script>
</body>
</html>
HTML

"$chromium" --headless=new --no-sandbox --disable-gpu \
    --allow-file-access-from-files \
    --blink-settings=primaryHoverType=2,availableHoverTypes=2,primaryPointerType=4,availablePointerTypes=4 \
    --virtual-time-budget=12000 \
    --dump-dom "file://$temporary/probe.html" > "$temporary/dom" 2>/dev/null || true

result=$(sed -n '/id="preview-check"/,/<\/pre>/p' "$temporary/dom" |
         sed 's|.*<pre id="preview-check">||; s|</pre>.*||; s|&lt;|<|g; s|&gt;|>|g; s|&amp;|\&|g')
printf '%s\n' "$result"

for expected in '"opened":true' '"hidden":false' '"focusable":1' '"closed":true' '"blurClosed":true' '"title":"Target section"' 'Anchor-specific body'; do
    if ! printf '%s\n' "$result" | grep -q "$expected"; then
        echo "preview-check: expected $expected" >&2
        exit 1
    fi
done
if printf '%s\n' "$result" | grep -q 'Page lead outside the anchor'; then
    echo "preview-check: anchor preview included page-level lead content" >&2
    exit 1
fi
