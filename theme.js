/* SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu> */
/* SPDX-License-Identifier: CC0-1.0 */

(() => {
  const root = document.documentElement;
  const system = window.matchMedia('(prefers-color-scheme: dark)');
  const key = 'flora-theme';
  let preference = null;
  let controls;
  let transitionTimer;

  function beginColorTransition() {
    clearTimeout(transitionTimer);
    root.classList.add('theme-transition');
    // Register transitions against the current colors before changing scheme.
    void root.offsetWidth;
    transitionTimer = setTimeout(() => root.classList.remove('theme-transition'), 220);
  }

  function readPreference() {
    try {
      const stored = localStorage.getItem(key);
      return stored === 'light' || stored === 'dark' ? stored : null;
    } catch (_) {
      return null;
    }
  }

  function apply() {
    const dark = preference ? preference === 'dark' : system.matches;
    root.dataset.theme = dark ? 'dark' : 'light';
    if (controls) {
      for (const input of controls.querySelectorAll('input')) {
        input.checked = input.value === (preference || 'system');
      }
    }
  }

  preference = readPreference();
  apply(); // Runs in the head, before stylesheets and the first paint.
  system.addEventListener('change', () => { if (!preference) apply(); });
  window.addEventListener('storage', (event) => {
    if (event.key === key || event.key === null) {
      preference = readPreference();
      apply();
    }
  });

  // Sidenotes are lifted into a page-level lane at render time. On wide
  // layouts, align each note with its in-text marker and push it down when
  // notes would overlap. Narrow layouts leave them as a normal endnote list.
  function alignSidenotes() {
    const lane = document.querySelector('.margin-lane');
    if (!lane) return;

    const notes = Array.from(lane.querySelectorAll(':scope > .margin-item'));
    const visibleNotes = [];
    for (const note of notes) {
      note.style.removeProperty('margin-block-start');
      const markerId = `margin-ref-${note.id.slice('margin-'.length)}`;
      const marker = document.getElementById(markerId);
      const collapsed = marker && marker.closest('details:not([open])');
      if (marker && !collapsed && marker.getClientRects().length > 0) {
        note.hidden = false;
        visibleNotes.push({ note, marker });
      } else {
        note.hidden = true;
      }
    }
    lane.hidden = visibleNotes.length === 0;
    if (!visibleNotes.length) return;
    if (!matchMedia('(width > 60rem)').matches) return;

    const laneTop = lane.getBoundingClientRect().top;
    const gap = parseFloat(getComputedStyle(lane).rowGap) || 0;
    let previousBottom = 0;
    for (const { note, marker } of visibleNotes) {
      const markerTop = Math.max(0, marker.getBoundingClientRect().top - laneTop);
      const naturalTop = previousBottom + (previousBottom ? gap : 0);
      const top = Math.max(naturalTop, markerTop);
      note.style.marginBlockStart = `${top - naturalTop}px`;
      previousBottom = top + note.getBoundingClientRect().height;
    }
  }

  function watchSidenotes() {
    let frame = 0;
    const schedule = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(alignSidenotes);
    };
    window.addEventListener('resize', schedule, { passive: true });
    document.querySelectorAll('details').forEach((details) => {
      details.addEventListener('toggle', schedule);
    });
    document.addEventListener('load', (event) => {
      if (event.target instanceof HTMLImageElement) schedule();
    }, true);
    window.addEventListener('load', schedule, { once: true });
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(schedule);
    schedule();
  }

  // Link previews, Gwern-style: hovering an internal link floats a card with
  // the target page's title and lead content. Nested links extend a preview
  // path, keeping each parent card open until the pointer leaves the path.
  function watchLinkPreviews() {
    if (!matchMedia('(hover: hover) and (pointer: fine)').matches) return;

    const PREFETCH_INTENT = 120; // start loading after a brief, steady hover
    const DISPLAY_INTENT = 500; // show the card only after clear pointer intent
    const MAX_CHARS = 1600;  // cap on extracted lead text
    const MAX_NODES = 6;     // cap on extracted block elements
    const SKIP = 'nav, .table-of-contents, .backmatter, .theme-controls, style, script, link, template, h1';
    const OMIT_CONTROLS = 'button, input, select, textarea, summary, [tabindex], ' +
      'audio[controls], video[controls], iframe, object, embed, form';
    const cache = new Map();
    const documentCache = new Map();
    const linkSelector = 'a[href]';
    const anchorPositioning =
      typeof CSS !== 'undefined' && CSS.supports &&
      CSS.supports('position-area: block-end') &&
      CSS.supports('position-anchor: --flora-link-preview');
    const stack = [];
    let hoverTimer = 0;
    let prefetchTimer = 0;
    let hideTimer = 0;
    let pending = null;
    let nextAnchorId = 0;
    let repositionFrame = 0;

    function previewHref(link) {
      try {
        const url = new URL(link.href, location.href);
        return url.origin === location.origin && url.pathname.endsWith('.html')
          ? url.href
          : null;
      } catch (_) {
        return null;
      }
    }

    function cardIndex(target) {
      const card = target && target.closest('.link-preview');
      return card ? stack.findIndex((item) => item.card === card) : -1;
    }

    function removeFrom(depth) {
      while (stack.length > depth) {
        const item = stack.pop();
        item.link.style.removeProperty('anchor-name');
        item.card.remove();
      }
    }

    function hideSoon() {
      clearTimeout(hideTimer);
      hideTimer = setTimeout(hide, 280);
    }

    function hide() {
      clearTimeout(hoverTimer);
      clearTimeout(prefetchTimer);
      clearTimeout(hideTimer);
      pending = null;
      removeFrom(0);
    }

    function extract(doc, baseUrl, fragment) {
      const article = doc.querySelector('article') || doc.body;
      let contentRoot = article;
      let titleElement = doc.querySelector('h1');
      if (fragment) {
        try {
          const anchor = doc.getElementById(decodeURIComponent(fragment.slice(1)));
          const tree = anchor && anchor.closest('.forest-tree-block');
          const treeTitle = tree && tree.querySelector(':scope > details > summary .forest-tree-title');
          const treeContent = tree && tree.querySelector(':scope > details > .forest-tree-content');
          if (treeTitle && treeContent) {
            titleElement = treeTitle;
            contentRoot = treeContent;
          }
        } catch (_) { /* An invalid fragment falls back to the page preview. */ }
      }
      let title = (titleElement || {}).textContent || '';
      // 预览卡片里,taxon 前缀与地址 chip 都是噪音。
      title = title.replace(/^(reference|chapter|index|tutorial|journal|code|person)\.\s+/i, "")
                   .replace(/\s*\[[^\]]*\]\s*$/, "")
                   .trim();
      const body = document.createElement('div');
      let chars = 0;
      for (const node of contentRoot.children) {
        if (node.matches(SKIP) || node.matches(OMIT_CONTROLS)) continue;
        const text = node.textContent;
        if (!text.trim()) continue;
        const clone = node.cloneNode(true);
        for (const gone of clone.querySelectorAll(SKIP)) gone.remove();
        // Keep internal links for nested previews; remove other interactive
        // controls and duplicate ids from the embedded fragment.
        for (const gone of clone.querySelectorAll(OMIT_CONTROLS)) {
          gone.remove();
        }
        for (const details of clone.querySelectorAll('details')) {
          details.replaceWith(...details.childNodes);
        }
        for (const element of [clone, ...clone.querySelectorAll('*')]) {
          for (const attribute of [...element.attributes]) {
            if (/^on/i.test(attribute.name) || attribute.name === 'id') {
              element.removeAttribute(attribute.name);
            }
          }
          if (element.matches('a[href]')) {
            try {
              element.href = new URL(element.getAttribute('href'), baseUrl).href;
              element.removeAttribute('target');
              element.removeAttribute('download');
            } catch (_) {
              element.replaceWith(...element.childNodes);
            }
          }
        }
        body.appendChild(clone);
        chars += text.length;
        if (body.children.length >= MAX_NODES || chars >= MAX_CHARS) break;
      }
      return { title, html: body.innerHTML };
    }

    function loadPreview(href) {
      const cached = cache.get(href);
      if (cached) return Promise.resolve(cached);
      const url = new URL(href);
      const fragment = url.hash;
      url.hash = '';
      const pageHref = url.href;
      let documentEntry = documentCache.get(pageHref);
      if (!documentEntry) {
        documentEntry = (async function () {
          const response = await fetch(pageHref);
          if (!response.ok) throw new Error(response.status);
          const baseUrl = response.url || pageHref;
          const doc = new DOMParser().parseFromString(await response.text(), 'text/html');
          return { doc, baseUrl };
        }());
        documentCache.set(pageHref, documentEntry);
        documentEntry.catch(() => documentCache.delete(pageHref));
      }
      const entry = documentEntry.then((resource) =>
        extract(resource.doc, resource.baseUrl, fragment));
      cache.set(href, entry);
      entry.catch(() => {
        if (cache.get(href) === entry) cache.delete(href);
      });
      return entry;
    }

    function place(item) {
      const rect = item.link.getBoundingClientRect();
      const width = item.card.offsetWidth;
      const height = item.card.offsetHeight;
      let left = rect.left + window.scrollX;
      left = Math.max(8, Math.min(left, window.scrollX + document.documentElement.clientWidth - width - 8));
      let top = rect.bottom + window.scrollY;
      if (rect.bottom + height > document.documentElement.clientHeight && rect.top - height > 0) {
        top = rect.top + window.scrollY - height;
      }
      item.card.style.left = `${left}px`;
      item.card.style.top = `${top}px`;
    }

    function reposition() {
      if (anchorPositioning || repositionFrame) return;
      repositionFrame = requestAnimationFrame(() => {
        repositionFrame = 0;
        for (const item of stack) place(item);
      });
    }

    function makeCard(link, depth) {
      const card = document.createElement('div');
      const anchorName = `--flora-link-preview-${++nextAnchorId}`;
      card.className = 'link-preview';
      card.setAttribute('aria-hidden', 'true');
      card.style.zIndex = String(60 + depth);
      if (anchorPositioning) {
        link.style.setProperty('anchor-name', anchorName);
        card.style.setProperty('position-anchor', anchorName);
      }
      document.body.appendChild(card);
      card.addEventListener('pointerenter', () => clearTimeout(hideTimer));
      const item = { link, card, depth };
      if (!anchorPositioning) place(item);
      return item;
    }

    async function showFor(link, parentDepth) {
      const href = previewHref(link);
      if (!href || pending?.link !== link || stack.length !== parentDepth) return;
      const item = makeCard(link, parentDepth);
      stack.push(item);
      item.card.classList.add('loading');
      try {
        const entry = await loadPreview(href);
        if (pending?.link !== link || stack[parentDepth] !== item) return;
        item.card.innerHTML = '';
        const heading = document.createElement('div');
        heading.className = 'link-preview-title';
        heading.textContent = entry.title;
        item.card.appendChild(heading);
        const body = document.createElement('div');
        body.className = 'link-preview-body';
        body.innerHTML = entry.html;
        item.card.appendChild(body);
        if (!anchorPositioning) place(item);
        item.card.classList.remove('loading');
        item.card.classList.add('open');
        item.card.setAttribute('aria-hidden', 'false');
      } catch (_) {
        if (stack[parentDepth] === item) removeFrom(parentDepth);
      }
    }

    function enter(link) {
      const href = previewHref(link);
      if (!href) return;
      const containingDepth = cardIndex(link);
      const parentDepth = containingDepth < 0 ? 0 : containingDepth + 1;
      const existing = stack[parentDepth];
      clearTimeout(hideTimer);
      if (existing?.link === link) {
        pending = { link, parentDepth };
        return;
      }
      clearTimeout(hoverTimer);
      clearTimeout(prefetchTimer);
      removeFrom(parentDepth);
      pending = { link, parentDepth };
      prefetchTimer = setTimeout(() => {
        if (pending?.link === link) loadPreview(href).catch(() => {});
      }, PREFETCH_INTENT);
      hoverTimer = setTimeout(() => showFor(link, parentDepth), DISPLAY_INTENT);
    }

    function isInOpenPath(target) {
      if (!target) return false;
      return stack.some((item) => item.card === target || item.card.contains(target) ||
        item.link === target || item.link.contains(target));
    }

    function prunePathAt(target) {
      const depth = cardIndex(target);
      const hoveredLink = target.closest(linkSelector);
      const matchingCard = hoveredLink
        ? stack.findIndex((item) => item.link === hoveredLink)
        : -1;
      const keepDepth = matchingCard >= 0 ? matchingCard + 1 : depth >= 0 ? depth + 1 : stack.length;
      if (stack.length > keepDepth) {
        clearTimeout(hoverTimer);
        clearTimeout(prefetchTimer);
        pending = null;
        removeFrom(keepDepth);
      }
    }

    document.addEventListener('pointerover', (event) => {
      const target = event.target instanceof Element ? event.target : null;
      const related = event.relatedTarget instanceof Element ? event.relatedTarget : null;
      if (!target) return;
      prunePathAt(target);
      if (isInOpenPath(target)) clearTimeout(hideTimer);
      const link = target.closest(linkSelector);
      const fromLink = related && related.closest(linkSelector);
      if (link && previewHref(link) && link !== fromLink) enter(link);
    });
    document.addEventListener('pointerout', (event) => {
      const target = event.target instanceof Element ? event.target : null;
      const related = event.relatedTarget instanceof Element ? event.relatedTarget : null;
      if (!target) return;
      const fromLink = target.closest(linkSelector);
      const toLink = related && related.closest(linkSelector);
      if (fromLink && fromLink !== toLink && !isInOpenPath(related)) {
        if (pending?.link === fromLink) {
          clearTimeout(hoverTimer);
          clearTimeout(prefetchTimer);
          pending = null;
        }
        hideSoon();
      }
      if (isInOpenPath(target) && !isInOpenPath(related)) hideSoon();
    });
    document.addEventListener('focusin', (event) => {
      const link = event.target.closest(linkSelector);
      if (link && previewHref(link)) {
        prunePathAt(link);
        enter(link);
      }
    });
    document.addEventListener('focusout', (event) => {
      const link = event.target.closest(linkSelector);
      if (!link) return;
      const next = event.relatedTarget;
      if (next && next.closest && next.closest(linkSelector)) return;
      hideSoon();
    });
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') hide();
    });
    window.addEventListener('scroll', reposition, true);
    window.addEventListener('resize', reposition);
  }

  document.addEventListener('DOMContentLoaded', () => {
    watchSidenotes();
    watchLinkPreviews();
    controls = document.querySelector('.theme-controls');
    if (!controls) return;
    controls.hidden = false;
    apply();
    controls.addEventListener('change', (event) => {
      if (!event.target.matches('input[name="flora-theme"]')) return;
      beginColorTransition();
      preference = event.target.value === 'system' ? null : event.target.value;
      try {
        if (preference) localStorage.setItem(key, preference);
        else localStorage.removeItem(key);
      } catch (_) { /* Session still works. */ }
      apply();
    });
  });
})();
