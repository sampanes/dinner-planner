// Kitchen mode: big-type, touch-first cooking view for the Echo Show 10.
// Data comes from data/runtime/recipes.runtime.json (built by
// scripts/build_runtime_data.py). Routes:
//   #/                 recipe picker
//   #/r/<slug>         recipe overview + ingredients
//   #/cook/<slug>/<n>  cook mode at step n (1-based)
'use strict';

const DATA_URL = 'data/runtime/recipes.runtime.json';
const HAVES_URL = 'data/runtime/haves.json';
const KEYS = { resume: 'kitchen.resume', timers: 'kitchen.timers', filter: 'kitchen.filter', size: 'kitchen.size', got: 'kitchen.got',
    kind: 'kitchen.kind', have: 'kitchen.have', shop: 'kitchen.shop' };

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
    kind: store.get(KEYS.kind, null),
    have: new Set(store.get(KEYS.have, [])),
    // slug -> Set of ingredient ids ticked off; kept so a reload (the Show's
    // browser drops pages it is not showing) does not untick everything.
    got: new Map(Object.entries(store.get(KEYS.got, {})).map(([slug, ids]) => [slug, new Set(ids)]))
};

function saveGot() {
    store.set(KEYS.got, Object.fromEntries([...state.got].filter(([, ids]) => ids.size).map(([slug, ids]) => [slug, [...ids]])));
}

// Ratings: what the repo says, with this device's not-yet-committed ratings on top (sync.js).
function rating(r) { return Sync.stars(r.slug, r.sourceStars); }
function stars(r) { const s = rating(r); return s.pink + s.blue; }
function isNew(r) { return stars(r) === 0; }
function isFav(r) { return stars(r) >= 8; }
function gotSet(slug) { if (!state.got.has(slug)) state.got.set(slug, new Set()); return state.got.get(slug); }

function starBadge(r) {
    if (isNew(r)) return h('span', { class: 'stars' }, 'Not rated yet');
    const s = rating(r);
    return h('span', { class: 'stars' },
        h('span', { class: 'p' }, String(s.pink)), ' / ',
        h('span', { class: 'b' }, String(s.blue)));
}

// "today", "3 days ago", "2 wks ago", "5 mo ago".
function ago(iso) {
    const days = Math.floor((Date.now() - Date.parse(iso)) / 86400e3);
    if (days < 1) return 'today';
    if (days < 2) return 'yesterday';
    if (days < 14) return `${days} days ago`;
    if (days < 60) return `${Math.round(days / 7)} wks ago`;
    return `${Math.round(days / 30)} mo ago`;
}
function lastMade(r) { const hist = Sync.history(r.slug); return hist.last ? `made ${ago(hist.last)}` : ''; }

// ---------- routing ----------
function parseRoute() {
    const parts = (location.hash || '#/').replace(/^#\/?/, '').split('/').filter(Boolean).map(decodeURIComponent);
    if (parts[0] === 'r' && bySlug.has(parts[1])) return { view: 'recipe', slug: parts[1] };
    if (parts[0] === 'cook' && bySlug.has(parts[1])) {
        const n = Math.max(1, parseInt(parts[2], 10) || 1);
        return { view: 'cook', slug: parts[1], step: n - 1 };
    }
    if (parts[0] === 'rate' && bySlug.has(parts[1])) return { view: 'rate', slug: parts[1], afterCooking: parts[2] === 'done' };
    if (parts[0] === 'shop') return { view: 'shop' };
    return { view: 'pick' };
}

function go(hash) { if (location.hash === hash) render(); else location.hash = hash; }

// Where the picker was scrolled to when a recipe was opened, so Back returns
// to the same tile instead of the top of 70 recipes.
let pickScroll = 0;
try { history.scrollRestoration = 'manual'; } catch (e) { /* older browsers */ }

function render() {
    const route = parseRoute();
    // Back from a recipe or the grocery list returns to the same spot; after
    // finishing a dinner the picker starts from the top again.
    const returning = route.view === 'pick' && (state.view === 'recipe' || state.view === 'shop');
    if (state.view === 'pick' && route.view !== 'pick') pickScroll = window.scrollY;
    leaveCook();
    closeSheets();
    window.scrollTo(0, 0);
    state.view = route.view;
    state.recipe = route.slug ? bySlug.get(route.slug) : null;
    if (route.view === 'recipe') renderRecipe(state.recipe);
    else if (route.view === 'cook') renderCook(state.recipe, route.step);
    else if (route.view === 'rate') renderRate(state.recipe, route.afterCooking);
    else if (route.view === 'shop') renderShop();
    else renderPick();
    if (returning && pickScroll) window.scrollTo(0, pickScroll);
}

// ---------- sheets ----------
// While a sheet is open the page behind it must not scroll under the finger.
const SHEETS = ['ingOverlay', 'timerOverlay', 'haveOverlay', 'decideOverlay'];
function openSheet(id) { $(id).hidden = false; document.documentElement.classList.add('sheet-open'); }
function closeSheet(id) {
    $(id).hidden = true;
    if (SHEETS.every(s => $(s).hidden)) document.documentElement.classList.remove('sheet-open');
}
function closeSheets() { SHEETS.forEach(closeSheet); }

// ---------- pick view ----------
// Three ways to narrow the list, all by tapping: who it is for (first chip row),
// what kind of dinner (second row: moods, then proteins), and what is already
// in the fridge (the "What do we have?" sheet). They combine.
function whoFilters() {
    const people = Sync.people();
    const anyCooked = recipes.some(r => Sync.history(r.slug).count);
    return [
        ['all', `All (${recipes.length})`, () => true],
        ['fav', 'Favorites', isFav],
        ['pink', `${people.pink}'s picks`, r => rating(r).pink >= 4, 'p'],
        ['blue', `${people.blue}'s picks`, r => rating(r).blue >= 4, 'b'],
        ['both', 'Both love it', r => rating(r).pink >= 4 && rating(r).blue >= 4],
        ['new', 'Not tried yet', isNew],
        anyCooked && ['while', 'Been a while', r => Sync.history(r.slug).count > 0]
    ].filter(Boolean);
}

function kindFilters() {
    const count = (fn) => recipes.filter(fn).length;
    const moods = [...new Set(recipes.flatMap(r => r.tags || []))];
    const proteins = [...new Set(recipes.flatMap(r => r.categories || []))];
    const order = (list, by) => list.sort((a, b) => by.indexOf(a) - by.indexOf(b));
    return [
        ...order(moods, MOOD_ORDER).map(m => [m, r => (r.tags || []).includes(m)]),
        ...order(proteins, PROTEIN_ORDER).map(p => [p, r => (r.categories || []).includes(p)])
    ].filter(([, fn]) => count(fn) >= 3);
}
const MOOD_ORDER = ['Tex-Mex', 'Pasta', 'Cheesy', 'Creamy', 'Spicy', 'Handhelds', 'Bowls & soups', 'Asian'];
const PROTEIN_ORDER = ['Beef', 'Chicken', 'Pork & sausage', 'Turkey', 'Seafood', 'Veggie'];

function haveCount(r) { return (r.haves || []).filter(x => state.have.has(x)).length; }

// The list the grid shows, in order.
function pickList() {
    const who = whoFilters().find(f => f[0] === state.filter) || whoFilters()[0];
    const kind = kindFilters().find(f => f[0] === state.kind);
    let list = recipes.filter(r => who[2](r) && (!kind || kind[1](r)));
    if (state.have.size) list = list.filter(r => haveCount(r) > 0);
    const byStars = (a, b) => (stars(b) - stars(a)) || a.displayName.localeCompare(b.displayName);
    if (who[0] === 'while') return list.sort((a, b) => Sync.history(a.slug).last.localeCompare(Sync.history(b.slug).last));
    if (state.have.size) return list.sort((a, b) => (haveCount(b) - haveCount(a)) || byStars(a, b));
    return list.sort(byStars);
}

function tile(r, small) {
    const meta = [starBadge(r)];
    if (state.have.size && !small) meta.push(` - has ${haveCount(r)} of ${state.have.size}`);
    else if (lastMade(r)) meta.push(` - ${lastMade(r)}`);
    else if (!small) meta.push(` - ${r.steps.length} steps`);
    return h('button', { class: 'tile' + (small ? ' small' : ''), type: 'button', onclick: () => go(`#/r/${r.slug}`) },
        h('img', { src: small ? imageAt(r.image, 240, 240) : imageAt(r.image, 400, 267), alt: '', loading: 'lazy', decoding: 'async' }),
        h('div', { class: 't-text' },
            h('div', { class: 't-name' }, r.displayName),
            h('div', { class: 't-meta' }, meta)));
}

// "ground beef, zucchini +2"
function haveSummary(max) {
    const all = [...state.have];
    return all.slice(0, max).join(', ') + (all.length > max ? ` +${all.length - max}` : '');
}

// One line above the grid that says what the taps added up to.
function pickSummary(count, whoLabel) {
    const parts = [];
    if (whoLabel) parts.push(whoLabel);
    if (state.kind) parts.push(state.kind);
    if (state.have.size) parts.push(`with ${haveSummary(3)}`);
    const n = `${count} recipe${count === 1 ? '' : 's'}`;
    return parts.length ? `${n}: ${parts.join(', ')}` : `${n}, best rated first`;
}

function planRecipes() {
    const plan = Sync.plan();
    return plan ? plan.slugs.map(s => bySlug.get(s)).filter(Boolean) : [];
}

// A chip or the "what do we have" sheet changed the list. On the Show the grid
// can start below the bottom edge (plan row + buttons + chips), so a tap would
// change nothing on screen: bring the buttons to the top with the results under them.
function showResults() {
    renderPick();
    const anchor = app.querySelector('.pick-actions');
    const count = app.querySelector('.pick-count');
    if (!anchor || !count) return;
    const room = window.innerHeight - count.getBoundingClientRect().top;
    if (room < window.innerHeight * 0.45) {
        window.scrollTo({ top: anchor.getBoundingClientRect().top + window.scrollY - topOffset() - 12, behavior: 'smooth' });
    }
}

function renderPick() {
    setTop('Kitchen', null);
    // Rebuilding the view must not snap the sideways-scrolled rows back to the start.
    const SIDE = ['.week-row', '.chips.who', '.chips.kinds'];
    const sideScroll = SIDE.map(sel => { const el = app.querySelector(sel); return el ? el.scrollLeft : 0; });
    const who = whoFilters();
    const activeWho = (who.find(f => f[0] === state.filter) || who[0])[0];
    const list = pickList();

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

    const planned = planRecipes();
    const week = planned.length ? h('section', { class: 'week' },
        h('div', { class: 'week-head' },
            h('h2', {}, 'This week'),
            h('button', { class: 'big-btn secondary', type: 'button', onclick: () => go('#/shop') }, 'Grocery list')),
        h('div', { class: 'week-row' }, planned.map(r => tile(r, true)))) : null;

    const actions = h('div', { class: 'pick-actions' },
        h('button', { class: 'big-btn primary', type: 'button', onclick: openDecide }, "Can't decide?"),
        h('button', { class: 'big-btn secondary' + (state.have.size ? ' on' : ''), type: 'button', onclick: openHave },
            state.have.size
                ? [h('span', { class: 'wide-only' }, `We have: ${haveSummary(5)}`), h('span', { class: 'narrow-only' }, `We have ${state.have.size}`)]
                : 'What do we have?'),
        state.have.size ? h('button', { class: 'big-btn secondary clear', type: 'button', onclick: () => { state.have.clear(); saveHave(); showResults(); } }, 'Clear') : null);

    const whoChips = h('div', { class: 'chips scroll who' }, who.map(([key, label, , cls]) =>
        h('button', {
            class: 'chip' + (key === activeWho ? ' on' : '') + (cls ? ` ${cls}` : ''), type: 'button',
            onclick: () => { state.filter = key; store.set(KEYS.filter, key); showResults(); }
        }, label)));

    const kindChips = h('div', { class: 'chips scroll kinds' }, kindFilters().map(([label]) =>
        h('button', {
            class: 'chip' + (label === state.kind ? ' on' : ''), type: 'button',
            onclick: () => { state.kind = state.kind === label ? null : label; store.set(KEYS.kind, state.kind); showResults(); }
        }, label)));

    const grid = h('div', { class: 'grid' }, list.map(r => tile(r, false)));
    const narrowed = activeWho !== 'all' || state.kind || state.have.size;
    const count = h('div', { class: 'pick-count' },
        h('span', {}, pickSummary(list.length, activeWho === 'all' ? '' : (who.find(f => f[0] === activeWho) || [])[1])),
        narrowed ? h('button', {
            class: 'chip reset', type: 'button',
            onclick: () => { state.filter = 'all'; state.kind = null; state.have.clear(); store.set(KEYS.filter, 'all'); store.set(KEYS.kind, null); saveHave(); showResults(); }
        }, 'Show all') : null);

    app.replaceChildren(resumeBtn || '', week || '', actions, whoChips, kindChips, count,
        list.length ? grid : h('p', { class: 'empty' }, activeWho === 'while' ? 'Nothing cooked yet.' : 'Nothing matches. Tap a chip again to turn it off.'));
    SIDE.forEach((sel, i) => { const el = app.querySelector(sel); if (el) el.scrollLeft = sideScroll[i]; });
}

// ---------- "What do we have?" sheet ----------
let haveCatalog = [];
function saveHave() { store.set(KEYS.have, [...state.have]); }

function openHave() { renderHave(); openSheet('haveOverlay'); }
function closeHave() { closeSheet('haveOverlay'); if (state.view === 'pick') showResults(); }
$('haveClose').addEventListener('click', closeHave);

function renderHave() {
    const groups = [...new Set(haveCatalog.map(x => x.group))];
    const matches = recipes.filter(r => haveCount(r) > 0).length;
    $('haveTitle').textContent = state.have.size ? `${matches} recipes use ${state.have.size === 1 ? 'it' : 'some of these'}` : 'Tap what you have';
    $('haveClose').textContent = state.have.size ? `Show ${matches}` : 'Close';
    $('haveList').replaceChildren(...groups.map(g => h('div', { class: 'have-group' },
        h('h3', {}, g),
        h('div', { class: 'have-grid' }, haveCatalog.filter(x => x.group === g).map(x =>
            h('button', {
                class: 'have' + (state.have.has(x.label) ? ' on' : ''), type: 'button',
                onclick: () => { if (state.have.has(x.label)) state.have.delete(x.label); else state.have.add(x.label); saveHave(); renderHave(); }
            }, x.label, h('span', { class: 'n' }, String(x.count))))))));
}

// ---------- "Can't decide?" ----------
// Three picks from whatever the chips currently show, weighted toward favorites
// and toward unrated recipes (so they get tried and rated), skipping anything
// cooked in the last week.
function decide() {
    let pool = pickList();
    if (pool.length < 3) pool = recipes.slice();
    const recent = r => { const last = Sync.history(r.slug).last; return last && Date.now() - Date.parse(last) < 7 * 86400e3; };
    if (pool.filter(r => !recent(r)).length >= 3) pool = pool.filter(r => !recent(r));
    const weight = r => isNew(r) ? 5 : 1 + stars(r);
    const picks = [];
    pool = pool.slice();
    while (picks.length < 3 && pool.length) {
        let roll = Math.random() * pool.reduce((sum, r) => sum + weight(r), 0);
        const i = pool.findIndex(r => (roll -= weight(r)) <= 0);
        picks.push(pool.splice(i < 0 ? 0 : i, 1)[0]);
    }
    return picks;
}

function openDecide() { renderDecide(); openSheet('decideOverlay'); }
function renderDecide() { $('decideList').replaceChildren(...decide().map(r => tile(r, false))); }
$('decideAgain').addEventListener('click', renderDecide);
$('decideClose').addEventListener('click', () => closeSheet('decideOverlay'));

// ---------- rate view ----------
function renderRate(r, afterCooking) {
    setTop(r.displayName, afterCooking ? null : `#/r/${r.slug}`);
    const people = Sync.people();
    const chosen = { ...rating(r) };
    const rows = ['pink', 'blue'].map(who => {
        const btns = [1, 2, 3, 4, 5].map(n => h('button', {
            class: 'star-btn', type: 'button', 'aria-label': `${n} stars`,
            onclick: () => { chosen[who] = chosen[who] === n ? 0 : n; paint(); }
        }, '★'));
        const paint = () => btns.forEach((b, i) => b.classList.toggle('on', i < chosen[who]));
        paint();
        return h('div', { class: `rate-row ${who === 'pink' ? 'p' : 'b'}` }, h('div', { class: 'rate-who' }, people[who]), h('div', { class: 'rate-stars' }, btns));
    });
    const before = rating(r);
    const save = () => {
        for (const who of ['pink', 'blue']) {
            if (chosen[who] !== before[who]) Sync.queue({ k: 'rate', slug: r.slug, who, stars: chosen[who] });
        }
        go(afterCooking ? '#/' : `#/r/${r.slug}`);
    };
    app.replaceChildren(h('div', { class: 'rate' },
        h('img', { src: imageAt(r.image, 600, 400), alt: '' }),
        h('div', { class: 'rate-main' },
            h('h1', {}, afterCooking ? 'How was it?' : 'Rate it'),
            h('p', { class: 'rate-hint' }, 'Tap a star. Tap it again to clear.'),
            rows,
            h('div', { class: 'rate-actions' },
                h('button', { class: 'big-btn primary', type: 'button', onclick: save }, 'Save'),
                h('button', { class: 'big-btn secondary', type: 'button', onclick: () => go(afterCooking ? '#/' : `#/r/${r.slug}`) }, afterCooking ? 'Skip' : 'Cancel')))));
}

// ---------- grocery list for this week's plan ----------
const PANTRY = new Set(['salt', 'pepper', 'oil', 'olive oil', 'butter', 'sugar', 'flour', 'water']);

// "20 ounce" + "10 ounce" + "1 1/2 cup" -> "30 ounce + 1 1/2 cup"; "2 unit" -> "2".
function parseAmount(text) {
    // "1 1/2 cup", "2/3 cup", "1.5 cup", "20 ounce"
    const m = /^(?:(\d+)\/(\d+)|(\d+(?:\.\d+)?)(?:\s+(\d+)\/(\d+))?)\s*(.*)$/.exec(text.trim());
    if (!m) return null;
    const n = m[1] ? m[1] / m[2] : parseFloat(m[3]) + (m[4] ? m[4] / m[5] : 0);
    return { n, unit: m[6].replace(/^units?$/i, '').trim() };
}
function fmtAmount(n) {
    const whole = Math.floor(n + 1e-9);
    const frac = n - whole;
    const parts = [[0, ''], [1 / 4, '1/4'], [1 / 3, '1/3'], [1 / 2, '1/2'], [2 / 3, '2/3'], [3 / 4, '3/4'], [1, '']];
    const [value, label] = parts.reduce((best, p) => Math.abs(p[0] - frac) < Math.abs(best[0] - frac) ? p : best);
    const w = whole + (value === 1 ? 1 : 0);
    return [w || (label ? '' : '0'), label].filter(Boolean).join(' ');
}
function totalAmounts(texts) {
    const sums = new Map();
    const loose = [];
    for (const t of texts) {
        const a = parseAmount(t);
        if (!a) { loose.push(t); continue; }
        sums.set(a.unit, (sums.get(a.unit) || 0) + a.n);
    }
    return [...[...sums].map(([unit, n]) => `${fmtAmount(n)} ${unit}`.trim()), ...loose].join(' + ');
}

function renderShop() {
    setTop('Grocery list', '#/');
    const plan = Sync.plan();
    const planned = planRecipes();
    if (!planned.length) { app.replaceChildren(h('p', { class: 'empty' }, 'No plan yet. Make one in the meal shuffler and tap "Send to kitchen".')); return; }
    const items = new Map();
    for (const r of planned) for (const ing of r.ingredients) {
        const key = ing.canonicalName || ing.id;
        if (!items.has(key)) items.set(key, { key, name: ing.displayName, amounts: [], meals: 0 });
        const item = items.get(key);
        if (ing.amountText && !/^to taste$/i.test(ing.amountText)) item.amounts.push(ing.amountText);
        item.meals++;
    }
    const saved = store.get(KEYS.shop, {});
    const checked = new Set(saved.plan === plan.id ? saved.checked : []);
    const row = (item) => {
        const btn = h('button', {
            class: 'shop-item' + (checked.has(item.key) ? ' got' : ''), type: 'button',
            onclick: () => {
                if (checked.has(item.key)) checked.delete(item.key); else checked.add(item.key);
                store.set(KEYS.shop, { plan: plan.id, checked: [...checked] });
                btn.classList.toggle('got', checked.has(item.key));
            }
        }, h('span', { class: 's-name' }, item.name),
            h('span', { class: 's-amt' }, [totalAmounts(item.amounts), item.meals > 1 ? ` (${item.meals} meals)` : ''].join('')));
        return h('li', {}, btn);
    };
    const all = [...items.values()].sort((a, b) => a.name.localeCompare(b.name));
    app.replaceChildren(h('div', { class: 'shop' },
        h('p', { class: 'ing-hint' }, `${planned.length} meals: ${planned.map(r => r.displayName).join(', ')}. Tap each item as it goes in the cart.`),
        h('ul', { class: 'ing-list shop-list' }, all.filter(i => !PANTRY.has(i.key)).map(row)),
        h('h2', {}, 'Probably in the pantry'),
        h('ul', { class: 'ing-list shop-list' }, all.filter(i => PANTRY.has(i.key)).map(row))));
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

function madeLine(r) {
    const hist = Sync.history(r.slug);
    return hist.count ? h('div', { class: 'meta made' }, `Made ${hist.count === 1 ? 'once' : `${hist.count} times`}, last ${ago(hist.last)}`) : null;
}

function renderRecipe(r) {
    setTop(r.displayName, '#/');
    const resume = store.get(KEYS.resume, null);
    const canResume = resume && resume.slug === r.slug && resume.step > 0;

    const actions = h('div', { class: 'actions' },
        canResume && h('button', { class: 'big-btn primary', type: 'button', onclick: () => go(`#/cook/${r.slug}/${resume.step + 1}`) },
            `Resume at step ${resume.step + 1}`),
        h('button', { class: 'big-btn ' + (canResume ? 'secondary' : 'primary'), type: 'button', onclick: () => go(`#/cook/${r.slug}/1`) },
            canResume ? 'Start over' : 'Start cooking'),
        h('button', { class: 'big-btn secondary', type: 'button', onclick: () => go(`#/rate/${r.slug}`) }, isNew(r) ? 'Rate it' : 'Change rating'));

    app.replaceChildren(h('div', { class: 'recipe' },
        h('div', { class: 'recipe-hero' },
            h('img', { src: imageAt(r.image, 600, 400), alt: '' }),
            h('h1', {}, r.displayName),
            h('div', { class: 'meta' }, starBadge(r), ` - ${r.ingredients.length} ingredients, ${r.steps.length} steps`),
            madeLine(r),
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
// compact the chips and drop the Alexa hint, then shrink to the 28px floor
// (26px and 20px on a phone, which is held close).
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
        const phone = window.innerWidth <= 600;
        shrinkTo(phone ? 26 : 34);
        if (el.offsetHeight > avail) el.classList.add('tight');
        shrinkTo(phone ? 20 : 28);
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

// Finishing logs the dinner (for "made 2 wks ago" and "Been a while") and asks for a rating.
function finishCooking() {
    store.del(KEYS.resume);
    const r = state.recipe;
    if (!r) { go('#/'); return; }
    state.got.delete(r.slug); saveGot();
    Sync.queue({ k: 'cooked', slug: r.slug });
    go(`#/rate/${r.slug}/done`);
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
    openSheet('ingOverlay');
});
$('ingClose').addEventListener('click', () => closeSheet('ingOverlay'));
// A tap on the dimmed edge around a sheet closes it, like its Close button.
for (const id of SHEETS) {
    $(id).addEventListener('click', (e) => {
        if (e.target !== $(id)) return;
        if (id === 'haveOverlay') closeHave(); else closeSheet(id);
    });
}

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

    // Top tray: soonest two (one on a phone), then a "+N" chip.
    const sorted = [...timers].sort((a, b) => (b.fired - a.fired) || (a.end - b.end));
    const room = window.innerWidth <= 600 ? 1 : 2;
    const chips = sorted.slice(0, room).map(t =>
        h('button', { class: 'timer-chip' + (t.fired ? ' done' : ''), type: 'button', onclick: openTimerSheet },
            h('span', { class: 't-time' }, t.fired ? 'DONE' : fmt(remaining(t))),
            h('span', { class: 't-label' }, t.label)));
    if (sorted.length > room) chips.push(h('button', { class: 'timer-chip more', type: 'button', onclick: openTimerSheet }, `+${sorted.length - room}`));
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

function openTimerSheet() { renderTimerSheet(); openSheet('timerOverlay'); }
$('timerClose').addEventListener('click', () => closeSheet('timerOverlay'));

function renderTimerSheet() {
    const rows = timers.map(t => h('div', { class: 'timer-row' },
        h('div', { class: 'tr-name' }, t.label),
        h('div', { class: 'tr-time' }, t.fired ? 'DONE' : fmt(remaining(t))),
        h('div', { class: 'tr-btns' },
            !t.fired && h('button', { class: 'big-btn secondary', type: 'button', onclick: () => { t.end += 60000; saveTimers(); tickTimers(); } }, '+1 min'),
            h('button', { class: 'big-btn danger', type: 'button', onclick: () => {
                timers = timers.filter(x => x !== t); saveTimers();
                if (!timers.some(x => x.fired)) { stopBeeping(); $('alarm').hidden = true; }
                tickTimers();
            } }, t.fired ? 'Clear' : 'Cancel'))));
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
        recipes = data.filter(r => r.steps && r.steps.length);
        recipes.forEach(r => bySlug.set(r.slug, r));
        const [catalog] = await Promise.all([
            fetch(HAVES_URL).then(res => res.ok ? res.json() : []).catch(() => []),
            Sync.load(Object.fromEntries(recipes.map(r => [r.slug, r.displayName])))
        ]);
        haveCatalog = catalog;
    } catch (e) {
        app.replaceChildren(h('p', { class: 'error' }, `Could not load recipes (${e.message}).`));
        return;
    }
    window.addEventListener('hashchange', render);
    render();
    if (timers.some(t => t.fired)) showAlarm();
}

init();
