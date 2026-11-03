// The live demo desktop on the Petal site: a clock that follows the visitor's
// time, apps typing lorem ipsum, a Petal menu that works, and six scenes that
// play as the story scrolls past.
(() => {
  'use strict';
  const desk = document.getElementById('desktop');
  if (!desk) return;

  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const rows = [...desk.querySelectorAll('.row')];
  const spaces = [...desk.querySelectorAll('.space')];
  const nameEl = document.getElementById('mb-name');
  const appEl = document.getElementById('mb-app');
  const petalButton = document.getElementById('mb-petal');

  const APPS = ['Notes', 'Editor', 'Terminal'];
  const DEFAULT = ['Desktop 1', 'Desktop 2', 'Desktop 3'];
  const NAMED = ['Writing', 'Code', 'Shell'];
  const TINTS = ['var(--c-orange)', 'var(--c-blue)', 'var(--c-green)'];

  // ---------- State and rendering ----------

  const fresh = () => ({
    names: DEFAULT.slice(), colors: [null, null, null], current: 0, menu: true,
    order: [0, 1, 2], editing: null, pressed: null, mc: false, tip: false,
  });
  let state = fresh();
  // The menu's switches. Scenes don't reset them; they're the visitor's.
  const prefs = { name: true, edge: true, login: true };

  function render() {
    const i = state.current;
    nameEl.textContent = state.names[i];
    appEl.textContent = APPS[i];
    desk.style.setProperty('--space', i);
    desk.style.setProperty('--flower', state.colors[i] || '#fff');
    desk.classList.toggle('menu-open', state.menu && !state.mc);
    desk.classList.toggle('mc', state.mc);
    desk.classList.toggle('tip', state.tip);
    desk.classList.toggle('no-name', !prefs.name);
    desk.classList.toggle('no-edge', !prefs.edge);
    spaces.forEach((space, k) => {
      space.querySelector('.wall-name').textContent = state.names[k];
      space.style.setProperty('--wall', state.colors[k] || '#fff');
      space.style.setProperty('--edge', state.colors[k] || 'transparent');
      space.classList.toggle('current', k === i);
      space.style.setProperty('--slot', state.order.indexOf(k));
    });
    petalButton.setAttribute('aria-expanded', String(state.menu));
    rows.forEach((row, k) => {
      const name = row.querySelector('.name');
      if (!name.isContentEditable) name.textContent = state.names[k];
      const dot = row.querySelector('.dot');
      dot.style.background = state.colors[k] || '';
      dot.classList.toggle('filled', Boolean(state.colors[k]));
      row.style.setProperty('--pos', state.order.indexOf(k));
      row.classList.toggle('current', k === i);
      row.classList.toggle('editing', state.editing === k);
      row.classList.toggle('pressed', state.pressed === k);
    });
  }

  // Scene timers. With reduced motion every step lands at once, in order.
  const timers = new Set();
  function later(ms, fn) {
    const t = setTimeout(() => { timers.delete(t); fn(); render(); }, reduce.matches ? 0 : ms);
    timers.add(t);
  }
  function cancel() {
    timers.forEach(clearTimeout);
    timers.clear();
  }

  // ---------- Scenes, one per story step ----------

  function typeName(k, word, start) {
    later(start, () => { state.editing = k; state.names[k] = ''; });
    [...word].forEach((ch, j) => later(start + 150 + j * 75, () => { state.names[k] += ch; }));
    const end = start + 150 + word.length * 75 + 250;
    later(end, () => { state.editing = null; });
    return end;
  }

  const named = () => Object.assign(fresh(), { names: NAMED.slice() });
  const colored = () => Object.assign(named(), { colors: TINTS.slice() });

  const scenes = {
    1() { state = fresh(); },
    2() {
      state = fresh();
      let t = 300;
      NAMED.forEach((word, k) => { t = typeName(k, word, t) + 150; });
    },
    3() {
      state = named();
      TINTS.forEach((color, k) => later(300 + k * 380, () => { state.colors[k] = color; }));
    },
    4() {
      state = colored();
      later(500, () => { state.pressed = 1; });
      later(850, () => { state.pressed = null; state.menu = false; state.current = 1; });
      later(2600, () => { state.menu = true; });
    },
    5() {
      state = Object.assign(colored(), { current: 1 });
      later(500, () => { state.pressed = 2; });
      later(950, () => { state.pressed = null; state.menu = false; state.mc = true; state.tip = true; });
      later(1900, () => { state.order = [2, 0, 1]; });
      later(3300, () => { state.mc = false; state.tip = false; state.menu = true; });
    },
    6() {
      state = Object.assign(colored(), { current: 1, order: [2, 0, 1] });
      later(400, () => { state.menu = false; state.mc = true; });
    },
  };

  let step = 0;
  function play(n) {
    if (n === step || !scenes[n]) return;
    step = n;
    cancel();
    desk.dataset.step = String(n);
    scenes[n]();
    render();
  }

  const stepEls = [...document.querySelectorAll('.step')];
  const stepObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      stepEls.forEach((el) => el.classList.toggle('active', el === entry.target));
      play(Number(entry.target.dataset.step));
    }
  }, { rootMargin: '-50% 0px -49% 0px' });
  stepEls.forEach((el) => stepObserver.observe(el));
  stepEls[0]?.classList.add('active');
  play(1);

  // ---------- The menu works: click to switch, double-click to rename, hold to reorder ----------

  petalButton.addEventListener('click', () => {
    cancel();
    state.menu = state.mc || !state.menu;
    state.mc = false;
    render();
  });

  // In Mission Control, clicking a thumbnail opens that Desktop, as on a Mac.
  spaces.forEach((space, k) => space.addEventListener('click', () => {
    if (!state.mc) return;
    cancel();
    state.mc = false;
    state.current = k;
    render();
  }));

  const sizeInput = document.getElementById('name-size');
  sizeInput.addEventListener('input', () => desk.style.setProperty('--name-scale', sizeInput.value / 160));
  sizeInput.addEventListener('pointerdown', () => desk.classList.add('previewing'));
  ['pointerup', 'pointercancel', 'blur'].forEach((type) => sizeInput.addEventListener(type, () => desk.classList.remove('previewing')));

  // Transition and duration: changing either plays it once, like the app's live preview.
  const transitionInput = document.getElementById('name-transition');
  const durationInput = document.getElementById('name-duration');
  const durationOut = document.getElementById('duration-out');
  let previewTimer;
  function previewTransition() {
    clearTimeout(previewTimer);
    desk.classList.remove('previewing');
    void desk.offsetWidth; // restart the animation
    desk.classList.add('previewing');
    previewTimer = setTimeout(() => desk.classList.remove('previewing'), Number(durationInput.value) * 1000 + 800);
  }
  transitionInput.addEventListener('change', () => {
    desk.style.setProperty('--name-anim', transitionInput.value);
    desk.classList.toggle('no-duration', transitionInput.value === 'none');
    previewTransition();
  });
  durationInput.addEventListener('input', () => {
    desk.style.setProperty('--name-dur', `${durationInput.value}s`);
    durationOut.textContent = `${Number(durationInput.value).toFixed(2)} s`;
  });
  durationInput.addEventListener('change', previewTransition);

  desk.querySelectorAll('.setting').forEach((button) => button.addEventListener('click', () => {
    const key = button.dataset.pref;
    prefs[key] = !prefs[key];
    button.setAttribute('aria-checked', String(prefs[key]));
    render();
  }));

  let suppressClick = false;
  rows.forEach((row, k) => {
    const name = row.querySelector('.name');
    let clickTimer;

    const switchTo = () => {
      cancel();
      state.pressed = null;
      state.current = k;
      state.menu = false;
      render();
    };

    row.addEventListener('click', (e) => {
      if (name.isContentEditable || suppressClick || e.detail > 1) return;
      cancel();
      state.pressed = k;
      render();
      clearTimeout(clickTimer);
      // Wait briefly in case this is the first half of a double-click.
      clickTimer = setTimeout(switchTo, reduce.matches ? 0 : 280);
    });

    row.addEventListener('dblclick', () => {
      clearTimeout(clickTimer);
      cancel();
      state.pressed = null;
      rename(k);
    });

    row.addEventListener('keydown', (e) => {
      if (name.isContentEditable) return;
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); switchTo(); }
      if (e.key === 'F2') { e.preventDefault(); rename(k); }
    });

    // Hold: Petal opens Mission Control, where the Desktop really moves. Here the drag is acted out.
    row.addEventListener('pointerdown', (e) => {
      if (name.isContentEditable || e.button !== 0) return;
      const hold = setTimeout(() => {
        clearTimeout(clickTimer);
        suppressClick = true;
        moveInMissionControl(k);
      }, 400);
      // The click that follows the release of a hold shouldn't switch Desktops.
      const stop = () => { clearTimeout(hold); setTimeout(() => { suppressClick = false; }, 50); };
      row.addEventListener('pointerup', stop, { once: true });
      row.addEventListener('pointercancel', stop, { once: true });
      row.addEventListener('pointerleave', stop, { once: true });
    });
  });

  function moveInMissionControl(k) {
    cancel();
    state.pressed = null;
    state.menu = false;
    state.mc = true;
    state.tip = true;
    render();
    later(900, () => { state.order = [k, ...state.order.filter((x) => x !== k)]; });
    later(2300, () => { state.mc = false; state.tip = false; state.menu = true; });
  }

  function rename(k) {
    const name = rows[k].querySelector('.name');
    const before = state.names[k];
    let cancelled = false;
    state.editing = k;
    render();
    name.contentEditable = 'true';
    name.focus();
    getSelection().selectAllChildren(name);

    const onKey = (e) => {
      e.stopPropagation();
      if (e.key === 'Enter') { e.preventDefault(); name.blur(); }
      if (e.key === 'Escape') { e.preventDefault(); cancelled = true; name.blur(); }
    };
    name.addEventListener('keydown', onKey);
    name.addEventListener('blur', () => {
      name.removeEventListener('keydown', onKey);
      name.contentEditable = 'false';
      const value = name.textContent.trim().slice(0, 32);
      // Same rule as the app: an empty name goes back to "Desktop N".
      state.names[k] = cancelled ? before : (value || DEFAULT[k]);
      state.editing = null;
      render();
    }, { once: true });
  }

  // ---------- Clock: the visitor's own date and time ----------

  const clock = document.getElementById('mb-clock');
  const parts = {
    weekday: new Intl.DateTimeFormat(undefined, { weekday: 'short' }),
    day: new Intl.DateTimeFormat(undefined, { day: 'numeric' }),
    month: new Intl.DateTimeFormat(undefined, { month: 'short' }),
    time: new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }),
  };
  function tick() {
    const now = new Date();
    clock.textContent = `${parts.weekday.format(now)} ${parts.day.format(now)} ${parts.month.format(now)} ${parts.time.format(now)}`;
    clock.dateTime = now.toISOString();
  }
  (function scheduleClock() {
    tick();
    setTimeout(scheduleClock, 60000 - (Date.now() % 60000) + 50);
  })();
  document.addEventListener('visibilitychange', () => { if (!document.hidden) tick(); });

  // ---------- Apps typing lorem ipsum ----------

  const SCRIPTS = {
    notes: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.\n\nUt enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.',
    code: 'import Lorem\n\nfunc ipsum(dolor: String) -> String {\n    let sit = "amet, consectetur"\n    for elit in dolor.split(" ") {\n        print(sit, elit)\n    }\n    return "adipiscing"\n}',
    shell: '$ lorem --ipsum dolor\nsit amet, consectetur adipiscing elit\n$ ipsum sed --do eiusmod\ntempor incididunt ut labore et dolore\n✓ magna aliqua\n$ ',
  };
  const typers = [...desk.querySelectorAll('.typed')].map((el) => ({ el, text: SCRIPTS[el.dataset.type] || '', pos: 0, wait: 0 }));

  let onScreen = true;
  new IntersectionObserver(([entry]) => { onScreen = entry.isIntersecting; }).observe(desk);

  setInterval(() => {
    if (reduce.matches) {
      typers.forEach((t) => { if (t.el.textContent !== t.text) t.el.textContent = t.text; });
      return;
    }
    if (!onScreen || document.hidden) return;
    for (const t of typers) {
      if (t.wait > 0) { t.wait -= 1; continue; }
      if (t.pos >= t.text.length) { t.pos = 0; t.el.textContent = ''; t.wait = 8; continue; }
      t.pos += 1;
      t.el.textContent = t.text.slice(0, t.pos);
      if (t.pos >= t.text.length) t.wait = 70;
    }
  }, 45);

  // ---------- OS switch: Mac works, Windows and Linux are coming ----------

  const tabs = [...document.querySelectorAll('.os-switch [role="tab"]')];
  const soonCard = document.getElementById('soon-card');
  const soonTitle = document.getElementById('soon-title');
  function selectOS(tab, focus) {
    tabs.forEach((t) => {
      const on = t === tab;
      t.setAttribute('aria-selected', String(on));
      t.tabIndex = on ? 0 : -1;
    });
    const os = tab.dataset.os;
    desk.dataset.os = os;
    soonCard.hidden = os === 'mac';
    if (os !== 'mac') soonTitle.textContent = `Petal for ${os === 'windows' ? 'Windows' : 'Linux'} is on the way.`;
    if (focus) tab.focus();
  }
  tabs.forEach((tab, i) => {
    tab.addEventListener('click', () => selectOS(tab));
    tab.addEventListener('keydown', (e) => {
      const d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (!d) return;
      e.preventDefault();
      selectOS(tabs[(i + d + tabs.length) % tabs.length], true);
    });
  });
})();
