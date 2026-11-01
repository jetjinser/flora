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
  // the target page's title and lead content. Fetch-on-demand with a short
  // intent delay and a per-session cache; click still navigates, touch
  // devices never see it, and math in the card is typeset after injection.
  function watchLinkPreviews() {
    if (!matchMedia('(hover: hover) and (pointer: fine)').matches) return;

    const INTENT = 180;      // ms of steady hover before a preview appears
    const MAX_CHARS = 1600;  // cap on extracted lead text
    const MAX_NODES = 6;     // cap on extracted block elements
    const SKIP = 'nav, .table-of-contents, .backmatter, .theme-controls, style, script, link, template, h1';
    const cache = new Map(); // href -> {title, html}
    // CSS anchor positioning handles placement and flipping; place() remains
    // the fallback for browsers without position-area/position-anchor.
    const anchorPositioning =
      typeof CSS !== 'undefined' && CSS.supports &&
      CSS.supports('position-area: block-end span-inline-end') &&
      CSS.supports('position-anchor: --flora-link-preview');
    let card = null;
    let currentLink = null;
    let currentHref = null;
    let hoverTimer = 0;
    let hideTimer = 0;

    function ensureCard() {
      if (!card) {
        card = document.createElement('div');
        card.className = 'link-preview';
        card.setAttribute('aria-hidden', 'true');
        document.body.appendChild(card);
        card.addEventListener('mouseenter', () => clearTimeout(hideTimer));
        card.addEventListener('mouseleave', hideSoon);
      }
      return card;
    }

    function setAnchor(link) {
      if (currentLink === link) return;
      if (currentLink) currentLink.style.removeProperty('anchor-name');
      currentLink = link;
      link.style.setProperty('anchor-name', '--flora-link-preview');
    }

    function hideSoon() {
      clearTimeout(hideTimer);
      hideTimer = setTimeout(hide, 120);
    }

    function hide() {
      clearTimeout(hoverTimer);
      if (card) {
        card.classList.remove('open');
        card.classList.remove('loading');
      }
      currentHref = null;
    }

    function extract(doc) {
      const article = doc.querySelector('article') || doc.body;
      let title = (doc.querySelector('h1') || {}).textContent || '';
      // 预览卡片里,taxon 前缀与地址 chip 都是噪音。
      title = title.replace(/^(reference|chapter|index|tutorial|journal|code|person)\.\s+/i, "")
                   .replace(/\s*\[[^\]]*\]\s*$/, "")
                   .trim();
      const body = document.createElement('div');
      let chars = 0;
      for (const node of article.children) {
        if (node.matches(SKIP)) continue;
        const text = node.textContent;
        if (!text.trim()) continue;
        const clone = node.cloneNode(true);
        for (const gone of clone.querySelectorAll(SKIP)) gone.remove();
        // The preview is visual-only: keep text and figures, drop every
        // focusable or interactive descendant and duplicate ids.
        for (const gone of clone.querySelectorAll(
          'a, button, input, select, textarea, summary, [tabindex], ' +
          'audio[controls], video[controls], iframe, object, embed, form')) {
          gone.remove();
        }
        for (const details of clone.querySelectorAll('details')) {
          details.replaceWith(...details.childNodes);
        }
        for (const label of clone.querySelectorAll('label[for]')) {
          label.removeAttribute('for');
        }
        for (const node of clone.querySelectorAll('[id]')) {
          node.removeAttribute('id');
        }
        body.appendChild(clone);
        chars += text.length;
        if (body.children.length >= MAX_NODES || chars >= MAX_CHARS) break;
      }
      return { title, html: body.innerHTML };
    }

    function place(link) {
      const rect = link.getBoundingClientRect();
      const width = card.offsetWidth;
      const height = card.offsetHeight;
      let left = rect.left + window.scrollX;
      left = Math.max(8, Math.min(left, window.scrollX + document.documentElement.clientWidth - width - 8));
      let top = rect.bottom + window.scrollY + 8;
      if (rect.bottom + height + 8 > window.scrollY + document.documentElement.clientHeight
          && rect.top - height - 8 > window.scrollY) {
        top = rect.top + window.scrollY - height - 8;
      }
      card.style.left = `${left}px`;
      card.style.top = `${top}px`;
    }

    async function showFor(link) {
      const href = link.getAttribute('href');
      if (!href) return;
      currentHref = href;
      const pending = ensureCard();
      pending.classList.add('loading');
      try {
        let entry = cache.get(href);
        if (!entry) {
          const response = await fetch(href);
          if (!response.ok) throw new Error(response.status);
          entry = extract(new DOMParser().parseFromString(await response.text(), 'text/html'));
          cache.set(href, entry);
        }
        if (currentHref !== href) return; // the pointer moved on mid-fetch
        pending.innerHTML = '';
        const heading = document.createElement('div');
        heading.className = 'link-preview-title';
        heading.textContent = entry.title;
        pending.appendChild(heading);
        const body = document.createElement('div');
        body.className = 'link-preview-body';
        body.innerHTML = entry.html;
        pending.appendChild(body);
        if (anchorPositioning) setAnchor(link);
        else place(link);
        if (window.MathJax && MathJax.typesetPromise) {
          MathJax.typesetPromise([pending]).catch(() => {});
        }
        pending.classList.remove('loading');
        pending.classList.add('open');
      } catch (_) {
        pending.classList.remove('loading'); // previews are optional; stay silent
      }
    }

    function enter(link) {
      if (link.closest('.link-preview')) return;
      const href = link.getAttribute('href');
      if (currentHref === href) return; // already showing this target
      hide();                    // 收起上一张;不得经 hideSoon 延时——它会反杀意图计时器
      clearTimeout(hoverTimer);
      hoverTimer = setTimeout(() => showFor(link), INTENT);
    }

    document.addEventListener('mouseover', (event) => {
      const link = event.target.closest('a[href$=".html"]');
      if (link && link.getAttribute('href').startsWith('/')) enter(link);
      else if (!event.target.closest('.link-preview')) hideSoon();
    });
    document.addEventListener('focusin', (event) => {
      const link = event.target.closest('a[href$=".html"]');
      if (link && link.getAttribute('href').startsWith('/')) enter(link);
    });
    document.addEventListener('focusout', (event) => {
      const link = event.target.closest('a[href$=".html"]');
      if (!link) return;
      const next = event.relatedTarget;
      if (next && next.closest && next.closest('a[href$=".html"]')) return;
      hideSoon();
    });
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') hide();
    });
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
