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

  // The contents lane and the margin notes share one column. When a note
  // crosses the contents, slide the contents aside on whichever side the
  // crossing demands less movement — lifted for notes arriving from below,
  // sunk beneath notes arriving from above — and let it settle back once the
  // note has passed. Without JS (or with reduced motion) the CSS veil erases
  // the overlap instead, so this is an enhancement, not a dependency.
  function watchContentsDodge() {
    const toc = document.querySelector('.table-of-contents');
    if (!toc) return;
    const notes = [...document.querySelectorAll('.flora-sidenote')];
    if (!notes.length) return;
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    const gap = 16;
    let applied = 0;   // signed: positive = slid up, negative = slid down
    let direction = 0; // chosen side for the current crossing: 1 up, -1 down
    let settleTimer = 0;
    let engageTimer = 0;
    let frame = 0;

    function measure() {
      frame = 0;
      // Read the live transform instead of compensating with `applied`:
      // during the eased settle-back the painted offset lags behind the
      // stored target, and using the stored value made the resting box look
      // higher than it is, re-engaging the dodge mid-return (the bouncing).
      const rect = toc.getBoundingClientRect();
      const style = getComputedStyle(toc).transform;
      const ty = style && style !== 'none' ? new DOMMatrixReadOnly(style).m42 : 0;
      const top = rect.top - ty;
      const bottom = top + rect.height;
      let up = 0;
      let down = 0;
      for (const note of notes) {
        const r = note.getBoundingClientRect();
        if (r.top >= bottom || r.bottom <= top) continue;
        up = Math.max(up, bottom - r.top + gap);
        down = Math.max(down, r.bottom + gap - top);
      }
      if (up === 0 && down === 0) {
        if (applied !== 0) {
          applied = 0;
          direction = 0;
          toc.style.transform = '';
          toc.classList.add('dodge-return');
          clearTimeout(settleTimer);
          settleTimer = setTimeout(() => toc.classList.remove('dodge-return'), 400);
        }
        return;
      }
      // Dodge to whichever side the crossing demands less movement, then
      // hold that side until the note has passed: a note entering from the
      // top edge (upward scrolls) sinks the contents beneath itself, one
      // entering from the bottom lifts it, and both grow 1:1 with the scroll.
      if (direction === 0) direction = up <= down ? 1 : -1;
      const shift = direction === 1
        ? Math.min(up, bottom + gap)
        : -Math.min(down, bottom + gap);
      if (shift === applied) return;
      clearTimeout(settleTimer);
      toc.classList.remove('dodge-return');
      // Ease a jump into the dodged state (e.g. a scroll teleport); the
      // tracking afterwards is exact.
      if (applied === 0) {
        toc.classList.add('dodge-engage');
        clearTimeout(engageTimer);
        engageTimer = setTimeout(() => toc.classList.remove('dodge-engage'), 180);
      } else {
        toc.classList.remove('dodge-engage');
      }
      applied = shift;
      toc.style.transform = `translate3d(0, ${-shift}px, 0)`;
    }

    function requestMeasure() {
      if (!frame) frame = requestAnimationFrame(measure);
    }

    addEventListener('scroll', requestMeasure, { passive: true });
    addEventListener('resize', requestMeasure);
    measure();
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
    let card = null;
    let currentHref = null;
    let hoverTimer = 0;
    let hideTimer = 0;

    function ensureCard() {
      if (!card) {
        card = document.createElement('div');
        card.className = 'link-preview';
        card.setAttribute('role', 'tooltip');
        document.body.appendChild(card);
        card.addEventListener('mouseenter', () => clearTimeout(hideTimer));
        card.addEventListener('mouseleave', hideSoon);
      }
      return card;
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
        place(link);
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
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') hide();
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    watchContentsDodge();
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
