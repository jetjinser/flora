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

  document.addEventListener('DOMContentLoaded', () => {
    watchContentsDodge();
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
