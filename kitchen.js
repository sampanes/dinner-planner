// Kitchen mode: big-type, touch-first cooking view for the Echo Show 10.
// Data comes from data/runtime/recipes.runtime.json (built by
// scripts/build_runtime_data.py). Routes:
//   #/                 recipe picker
//   #/r/<slug>         recipe overview + ingredients
//   #/cook/<slug>/<n>  cook mode at step n (1-based)
'use strict';

const DATA_URL = 'data/runtime/recipes.runtime.json';
const KEYS = { resume: 'kitchen.resume', timers: 'kitchen.timers', filter: 'kitchen.filter', size: 'kitchen.size', got: 'kitchen.got' };

// ---------- storage (never required: private windows and previews can block it) ----------
const store = {
    get(key, fallback) {
        try { const v = localStorage.getItem(key); return v == null ? fallback : JSON.parse(v); }
        catch (e) { return fallback; }
    },
    set(key, value) { try { localStorage.setItem(key, JSON.stringify(value)); } catch (e) { /* ignore */ } },
    del(key) { try { localStorage.removeItem(key); } catch (e) { /* ignore */ } }
};

// ---------- tiny DOM helper (textContent only, so recipe text is never parsed as HTML) ----------
function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
        if (v == null || v === false) continue;
        if (k === 'class') el.className = v;
        else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
        else el.setAttribute(k, v === true ? '' : v);
    }
    for (const c of children.flat(Infinity)) {
        if (c == null || c === false) continue;
        el.append(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return el;
}

const $ = (id) => document.getElementById(id);
const app = $('app');

// Mirrors imageAt() in app.js / image_at() in scripts/hellofresh.py.
function imageAt(url, width, height) {
    if (!url) return url;
    if (url.startsWith('https://img.hellofresh.com/c_fill,w_1200,h_800,f_auto,q_auto/')) {
        return url.replace('c_fill,w_1200,h_800,f_auto,q_auto', `c_fill,w_${width},h_${height},f_auto,q_auto`);
    }
    if (url.startsWith('https://images.unsplash.com/')) {
        return url.replace('w=1200&h=800', `w=${width}&h=${height}`);
    }
    return url;
}

// ---------- state ----------
let recipes = [];
const bySlug = new Map();
const state = {
    view: 'pick',
    recipe: null,
    step: 0,
    filter: store.get(KEYS.filter, 'all'),
    // slug -> Set of ingredient ids ticked off; kept so a reload (the Show's
    // browser drops pages it is not showing) does not untick everything.
    got: new Map(Object.entries(store.get(KEYS.got, {})).map(([slug, ids]) => [slug, new Set(ids)]))
};

function saveGot() {
    store.set(KEYS.got, Object.fromEntries([...state.got].filter(([, ids]) => ids.size).map(([slug, ids]) => [slug, [...ids]])));
}

function stars(r) { return (r.sourceStars && (r.sourceStars.pink || 0) + (r.sourceStars.blue || 0)) || 0; }
function isNew(r) { return stars(r) === 0; }
function isFav(r) { return stars(r) >= 8; }
function gotSet(slug) { if (!state.got.has(slug)) state.got.set(slug, new Set()); return state.got.get(slug); }

function starBadge(r) {
    if (isNew(r)) return h('span', { class: 'stars' }, 'Not rated yet');
    return h('span', { class: 'stars' },
        h('span', { class: 'p' }, String(r.sourceStars.pink || 0)), ' / ',
        h('span', { class: 'b' }, String(r.sourceStars.blue || 0)));
}

// ---------- routing ----------
function parseRoute() {
    const parts = (location.hash || '#/').replace(/^#\/?/, '').split('/').filter(Boolean).map(decodeURIComponent);
    if (parts[0] === 'r' && bySlug.has(parts[1])) return { view: 'recipe', slug: parts[1] };
    if (parts[0] === 'cook' && bySlug.has(parts[1])) {
        const n = Math.max(1, parseInt(parts[2], 10) || 1);
        return { view: 'cook', slug: parts[1], step: n - 1 };
    }
    return { view: 'pick' };
}

function go(hash) { if (location.hash === hash) render(); else location.hash = hash; }

function render() {
    const route = parseRoute();
    leaveCook();
    window.scrollTo(0, 0);
    state.view = route.view;
    state.recipe = route.slug ? bySlug.get(route.slug) : null;
    if (route.view === 'recipe') renderRecipe(state.recipe);
    else if (route.view === 'cook') renderCook(state.recipe, route.step);
    else renderPick();
}

// ---------- pick view ----------
function renderPick() {
    setTop('Kitchen', null);
    const filters = [
        ['all', `All (${recipes.length})`, () => true],
        ['fav', 'Favorites', isFav],
        ['new', 'Not tried yet', isNew]
    ];
    const active = filters.find(f => f[0] === state.filter) || filters[0];
    const list = recipes.filter(active[2]);

    const resume = store.get(KEYS.resume, null);
    const resumeRecipe = resume && bySlug.get(resume.slug);
    const resumeBtn = resumeRecipe && h('button', {
        class: 'resume', type: 'button',
        onclick: () => go(`#/cook/${resumeRecipe.slug}/${resume.step + 1}`)
    },
        h('div', {},
            h('div', { class: 'r-kicker' }, `Keep cooking - step ${resume.step + 1} of ${resumeRecipe.steps.length}`),
            h('div', { class: 'r-name' }, resumeRecipe.displayName)),
        h('div', { class: 'r-go' }, 'Resume >'));

    const chips = h('div', { class: 'chips' }, filters.map(([key, label]) =>
        h('button', {
            class: 'chip' + (key === active[0] ? ' on' : ''), type: 'button',
            onclick: () => { state.filter = key; store.set(KEYS.filter, key); renderPick(); }
        }, label)));

    const grid = h('div', { class: 'grid' }, list.map(r =>
        h('button', { class: 'tile', type: 'button', onclick: () => go(`#/r/${r.slug}`) },
            h('img', { src: imageAt(r.image, 400, 267), alt: '', loading: 'lazy', decoding: 'async' }),
            h('div', { class: 't-name' }, r.displayName),
            h('div', { class: 't-meta' }, starBadge(r), ` - ${r.steps.length} steps`))));

    app.replaceChildren(resumeBtn || '', chips,
        list.length ? grid : h('p', { class: 'empty' }, 'Nothing here yet.'));
}

// ---------- recipe view ----------
function ingredientButtons(r) {
    const got = gotSet(r.slug);
    return r.ingredients.map(ing => {
        const btn = h('button', {
            type: 'button', class: got.has(ing.id) ? 'got' : '',
            onclick: () => {
                if (got.has(ing.id)) got.delete(ing.id); else got.add(ing.id);
                saveGot();
                btn.classList.toggle('got', got.has(ing.id));
            }
        }, ing.text || `${ing.amountText} ${ing.displayName}`.trim());
        return h('li', {}, btn);
    });
}

function renderRecipe(r) {
    setTop(r.displayName, '#/');
    const resume = store.get(KEYS.resume, null);
    const canResume = resume && resume.slug === r.slug && resume.step > 0;

    const actions = h('div', { class: 'actions' },
        canResume && h('button', { class: 'big-btn primary', type: 'button', onclick: () => go(`#/cook/${r.slug}/${resume.step + 1}`) },
            `Resume at step ${resume.step + 1}`),
        h('button', { class: 'big-btn ' + (canResume ? 'secondary' : 'primary'), type: 'button', onclick: () => go(`#/cook/${r.slug}/1`) },
            canResume ? 'Start over' : 'Start cooking'));

    app.replaceChildren(h('div', { class: 'recipe' },
        h('div', { class: 'recipe-hero' },
            h('img', { src: imageAt(r.image, 600, 400), alt: '' }),
            h('h1', {}, r.displayName),
            h('div', { class: 'meta' }, starBadge(r), ` - ${r.ingredients.length} ingredients, ${r.steps.length} steps`),
            actions),
        h('div', { class: 'recipe-side' },
            h('h2', {}, 'Ingredients'),
            h('p', { class: 'ing-hint' }, 'Tap each one as you set it out.'),
            h('ul', { class: 'ing-list' }, ingredientButtons(r)),
            r.notes && r.notes.length ? h('div', { class: 'notes' }, r.notes.map(n => h('p', {}, n))) : null)));
}

// ---------- cook view ----------
let stepEls = [];
let scrollTimer = null;

// The build names what each timer is for ("penne pasta", "bake"); a section
// title or the step number is the fallback.
function timerLabel(step, i, hint) { return (hint && hint.label) || step.section || `step ${i + 1}`; }

// "5-6 minutes" -> "5-6 min", so the button reads "Start 5-6 min timer".
function shortTime(text) {
    return text.replace(/\b(minutes?|mins?)\b/i, 'min').replace(/\b(seconds?|secs?)\b/i, 'sec').replace(/\b(hours?|hrs?)\b/i, 'hr');
}

// Sub-minute hints ("until fragrant, 30 seconds") are not worth a timer button.
function usefulTimers(step) { return (step.timerHints || []).filter(t => t.seconds >= 60); }

function alexaPhrase(seconds, label) {
    const n = seconds < 60 ? seconds : Math.round(seconds / 60);
    const amount = seconds < 60 ? `${n} second` : `${n} minute`;
    const article = /^(8|11|18)$|^8\d$/.test(String(n)) ? 'an' : 'a';
    return `or say "Alexa, set ${article} ${amount} timer for ${label.toLowerCase()}"`;
}

function renderCook(r, startStep) {
    setTop(r.displayName, `#/r/${r.slug}`);
    document.documentElement.classList.add('cook-mode');
    document.body.classList.add('cooking');
    $('cookbar').hidden = false;
    app.style.padding = '0';

    const byId = new Map(r.ingredients.map(i => [i.id, i]));
    const total = r.steps.length;

    stepEls = r.steps.map((step, i) => {
        const uses = (step.ingredientRefs || []).map(id => byId.get(id)).filter(Boolean);
        const hints = usefulTimers(step);
        return h('section', { class: 'step', 'data-i': i },
            h('div', { class: 'step-head' },
                h('div', { class: 'step-section' }, step.section || ''),
                h('div', { class: 'step-count' }, `Step ${i + 1} of ${total}`)),
            h('p', { class: 'step-text' }, step.displayText),
            uses.length ? h('div', { class: 'step-uses' }, uses.map(u => h('span', {}, u.text || u.displayName))) : null,
            hints.length ? h('div', { class: 'step-timers' },
                hints.map(t => h('button', { class: 'big-btn primary timer-btn', type: 'button', onclick: () => startTimer(timerLabel(step, i, t), t.seconds) },
                    h('span', { class: 'tb-time' }, `Start ${shortTime(t.text)} timer`),
                    h('span', { class: 'tb-label' }, timerLabel(step, i, t)))),
                h('span', { class: 'say' }, alexaPhrase(hints[0].seconds, timerLabel(step, i, hints[0])))) : null);
    });

    const done = h('section', { class: 'step done-step', 'data-i': total },
        h('p', { class: 'step-text' }, 'All done. Enjoy!'),
        h('button', { class: 'big-btn primary huge', type: 'button', onclick: finishCooking }, 'Finish'));
    stepEls.push(done);

    app.replaceChildren(...stepEls);
    requestWakeLock();
    // Reading offsetHeight forces layout, so this works without waiting a frame.
    fitSteps();
    goToStep(Math.min(startStep, total - 1), false);
}

function leaveCook() {
    document.documentElement.classList.remove('cook-mode');
    document.body.classList.remove('cooking');
    $('cookbar').hidden = true;
    app.style.padding = '';
    stepEls = [];
    stopSpeaking();
    releaseWakeLock();
}

function topOffset() { return $('topbar').offsetHeight; }

// Shrink the text of any step that would not fit on one screen, so every step
// is readable without scrolling inside it: first shrink the text to 34px, then
// compact the chips and drop the Alexa hint, then shrink to the 28px floor.
function fitSteps() {
    const avail = window.innerHeight - topOffset() - $('cookbar').offsetHeight;
    for (const el of stepEls) {
        const text = el.querySelector('.step-text');
        if (!text) continue;
        text.style.fontSize = '';
        el.classList.remove('tight');
        let px = parseFloat(getComputedStyle(text).fontSize);
        const shrinkTo = (floor) => {
            while (el.offsetHeight > avail && px > floor) { px -= 2; text.style.fontSize = `${px}px`; }
        };
        shrinkTo(34);
        if (el.offsetHeight > avail) el.classList.add('tight');
        shrinkTo(28);
    }
}

let resizeTimer = null;
window.addEventListener('resize', () => {
    if (state.view !== 'cook') return;
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { fitSteps(); goToStep(state.step, false); }, 150);
});

function goToStep(i, smooth) {
    if (!stepEls.length) return;
    i = Math.max(0, Math.min(i, stepEls.length - 1));
    const top = stepEls[i].getBoundingClientRect().top + window.scrollY - topOffset();
    // While our own smooth scroll is moving, the scroll listener must not read
    // the in-between position back as the current step.
    scrollLockUntil = smooth ? Date.now() + 1500 : 0;
    scrollTarget = i;
    window.scrollTo({ top, behavior: smooth ? 'smooth' : 'auto' });
    setStep(i);
}

let scrollTarget = null;
let scrollLockUntil = 0;

function setStep(i) {
    const r = state.recipe;
    if (!r || state.view !== 'cook') return;
    const total = r.steps.length;
    state.step = i;
    $('progressFill').style.width = `${Math.round(Math.min(i + 1, total) / total * 100)}%`;
    $('prevBtn').disabled = i === 0;
    $('nextBtn').textContent = i >= total - 1 ? (i >= total ? 'Finish' : 'Done >') : 'Next >';
    if (i < total) {
        history.replaceState(null, '', `#/cook/${r.slug}/${i + 1}`);
        store.set(KEYS.resume, { slug: r.slug, step: i });
    }
}

// Pick the step whose top is closest to the bar after any scroll (swipe, keys, voice scroll).
function stepFromScroll() {
    const top = topOffset();
    let best = 0, bestDist = Infinity;
    stepEls.forEach((el, i) => {
        const d = Math.abs(el.getBoundingClientRect().top - top);
        if (d < bestDist) { bestDist = d; best = i; }
    });
    return best;
}

window.addEventListener('scroll', () => {
    if (state.view !== 'cook' || !stepEls.length) return;
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(() => {
        const i = stepFromScroll();
        if (scrollTarget !== null) {
            if (i === scrollTarget || Date.now() > scrollLockUntil) scrollTarget = null;
            else return;
        }
        if (i !== state.step) { stopSpeaking(); setStep(i); }
    }, 120);
}, { passive: true });

function nextStep() {
    if (state.step >= stepEls.length - 1) { finishCooking(); return; }
    stopSpeaking();
    goToStep(state.step + 1, true);
}
function prevStep() { stopSpeaking(); goToStep(state.step - 1, true); }

function finishCooking() {
    store.del(KEYS.resume);
    if (state.recipe) { state.got.delete(state.recipe.slug); saveGot(); }
    go('#/');
}

$('nextBtn').addEventListener('click', nextStep);
$('prevBtn').addEventListener('click', prevStep);

document.addEventListener('keydown', (e) => {
    if (state.view !== 'cook') return;
    if (e.key === 'ArrowRight' || e.key === 'ArrowDown' || e.key === 'PageDown' || e.key === ' ') { e.preventDefault(); nextStep(); }
    else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp' || e.key === 'PageUp') { e.preventDefault(); prevStep(); }
});

// Ingredients sheet
$('ingBtn').addEventListener('click', () => {
    if (!state.recipe) return;
    $('ingOverlayList').replaceChildren(...ingredientButtons(state.recipe));
    $('ingOverlay').hidden = false;
});
$('ingClose').addEventListener('click', () => { $('ingOverlay').hidden = true; });

// ---------- read aloud (only shown if the browser has speech synthesis) ----------
const canSpeak = 'speechSynthesis' in window && typeof window.SpeechSynthesisUtterance === 'function';
if (canSpeak) $('readBtn').hidden = false;

function stopSpeaking() { if (canSpeak) { try { window.speechSynthesis.cancel(); } catch (e) { /* ignore */ } } }

$('readBtn').addEventListener('click', () => {
    const r = state.recipe;
    if (!canSpeak || !r || state.step >= r.steps.length) return;
    stopSpeaking();
    const step = r.steps[state.step];
    window.speechSynthesis.speak(new SpeechSynthesisUtterance(step.speakShort || step.displayText));
});

// ---------- keep the screen on while cooking (where supported) ----------
let wakeLock = null;
async function requestWakeLock() {
    if (!('wakeLock' in navigator) || state.view !== 'cook') return;
    try { wakeLock = await navigator.wakeLock.request('screen'); } catch (e) { wakeLock = null; }
}
function releaseWakeLock() { if (wakeLock) { wakeLock.release().catch(() => {}); wakeLock = null; } }
document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') { requestWakeLock(); tickTimers(); }
});

// ---------- timers (stored as end times, so a reload keeps them) ----------
let timers = store.get(KEYS.timers, []).filter(t => t && t.end && !t.dismissed);
let audioCtx = null;
let beepLoop = null;

function saveTimers() { store.set(KEYS.timers, timers); }

function unlockAudio() {
    // Browsers only allow sound after a tap; create the context on the first one.
    try {
        if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        if (audioCtx.state === 'suspended') audioCtx.resume();
    } catch (e) { audioCtx = null; }
}
document.addEventListener('pointerdown', unlockAudio, { passive: true });

function beepOnce() {
    if (!audioCtx) return;
    const now = audioCtx.currentTime;
    [0, 0.25, 0.5].forEach(offset => {
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.type = 'square';
        osc.frequency.value = 880;
        gain.gain.setValueAtTime(0.0001, now + offset);
        gain.gain.exponentialRampToValueAtTime(0.4, now + offset + 0.02);
        gain.gain.exponentialRampToValueAtTime(0.0001, now + offset + 0.18);
        osc.connect(gain).connect(audioCtx.destination);
        osc.start(now + offset);
        osc.stop(now + offset + 0.2);
    });
}

function startTimer(label, seconds) {
    unlockAudio();
    timers.push({ id: Date.now() + Math.random(), label, end: Date.now() + seconds * 1000, fired: false, dismissed: false });
    saveTimers();
    tickTimers();
}

function remaining(t) { return Math.max(0, Math.ceil((t.end - Date.now()) / 1000)); }
function fmt(sec) {
    const m = Math.floor(sec / 60), s = sec % 60;
    return m >= 60 ? `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}:${String(s).padStart(2, '0')}` : `${m}:${String(s).padStart(2, '0')}`;
}

function tickTimers() {
    let newlyDone = null;
    for (const t of timers) {
        if (!t.fired && remaining(t) === 0) { t.fired = true; newlyDone = t; }
    }
    if (newlyDone) { saveTimers(); showAlarm(); }

    // Top tray: soonest two, then a "+N" chip.
    const sorted = [...timers].sort((a, b) => (b.fired - a.fired) || (a.end - b.end));
    const chips = sorted.slice(0, 2).map(t =>
        h('button', { class: 'timer-chip' + (t.fired ? ' done' : ''), type: 'button', onclick: openTimerSheet },
            h('span', { class: 't-time' }, t.fired ? 'DONE' : fmt(remaining(t))),
            h('span', { class: 't-label' }, t.label)));
    if (sorted.length > 2) chips.push(h('button', { class: 'timer-chip more', type: 'button', onclick: openTimerSheet }, `+${sorted.length - 2}`));
    $('timerTray').replaceChildren(...chips);

    if (!$('timerOverlay').hidden) renderTimerSheet();
    $('clock').textContent = new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

function showAlarm() {
    const due = timers.filter(t => t.fired);
    if (!due.length) return;
    $('alarmName').textContent = due.map(t => t.label).join(', ');
    $('alarm').hidden = false;
    if (!beepLoop) {
        beepOnce();
        let count = 0;
        beepLoop = setInterval(() => { beepOnce(); if (++count > 200) stopBeeping(); }, 1500);
    }
}
function stopBeeping() { clearInterval(beepLoop); beepLoop = null; }

$('alarmDismiss').addEventListener('click', () => {
    timers = timers.filter(t => !t.fired);
    saveTimers();
    stopBeeping();
    $('alarm').hidden = true;
    tickTimers();
});

function openTimerSheet() { renderTimerSheet(); $('timerOverlay').hidden = false; }
$('timerClose').addEventListener('click', () => { $('timerOverlay').hidden = true; });

function renderTimerSheet() {
    const rows = timers.map(t => h('div', { class: 'timer-row' },
        h('div', { class: 'tr-name' }, t.label),
        h('div', { class: 'tr-time' }, t.fired ? 'DONE' : fmt(remaining(t))),
        !t.fired && h('button', { class: 'big-btn secondary', type: 'button', onclick: () => { t.end += 60000; saveTimers(); tickTimers(); } }, '+1 min'),
        h('button', { class: 'big-btn danger', type: 'button', onclick: () => {
            timers = timers.filter(x => x !== t); saveTimers();
            if (!timers.some(x => x.fired)) { stopBeeping(); $('alarm').hidden = true; }
            tickTimers();
        } }, t.fired ? 'Clear' : 'Cancel')));
    $('timerSheetList').replaceChildren(...(rows.length ? rows : [h('p', { class: 'empty' }, 'No timers running.')]));
}

setInterval(tickTimers, 500);

// ---------- top bar ----------
function setTop(title, backHash) {
    $('topTitle').textContent = title;
    const back = $('backBtn');
    back.hidden = !backHash;
    back.onclick = backHash ? () => go(backHash) : null;
}

let size = store.get(KEYS.size, 1);
function applySize() { document.documentElement.classList.remove('size-0', 'size-1', 'size-2'); document.documentElement.classList.add(`size-${size}`); }
$('sizeBtn').addEventListener('click', () => {
    size = (size + 1) % 3; store.set(KEYS.size, size); applySize();
    if (state.view === 'cook') { fitSteps(); goToStep(state.step, false); }
});
applySize();

// ---------- boot ----------
async function init() {
    tickTimers();
    try {
        const res = await fetch(DATA_URL);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        recipes = data.filter(r => r.steps && r.steps.length)
            .sort((a, b) => (stars(b) - stars(a)) || a.displayName.localeCompare(b.displayName));
        recipes.forEach(r => bySlug.set(r.slug, r));
    } catch (e) {
        app.replaceChildren(h('p', { class: 'error' }, `Could not load recipes (${e.message}).`));
        return;
    }
    window.addEventListener('hashchange', render);
    render();
    if (timers.some(t => t.fired)) showAlarm();
}

init();
