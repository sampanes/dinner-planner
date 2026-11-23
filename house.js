// The phones' shared plan, read by the kitchen screen.
//
// The phone app (apps/dinner_planner) keeps who cooks what on which day in a
// private ntfy topic that only the household knows; nothing about it is in this
// repo. A device linked here with the household code joins that topic as a
// listener: it never writes a plan entry, it only folds in what the phones send
// and tells them, through the same "dp2" messages the phones use, what it holds
// (a digest of its copy). A phone that hears a digest unlike its own sends what
// may be missing, which is how a screen linked today learns a plan made last
// week even though ntfy forgets messages after about twelve hours.
//
// Mirrors apps/dinner_planner/lib/core/sync_core.dart (Entry, digest) and
// lib/data/relay.dart (Household codes, the wire line). Keep them in step.
//
// Linking a screen whose keyboard is hard to use: the screen shows a short
// pairing code and listens on "dp-pair-<code>"; a phone browser pastes the
// household code and sends it there.
'use strict';

const House = (() => {
    const KEY = 'kitchen.house';
    const WIRE = 'dp2 ';
    const PAIR_WIRE = 'dppair ';
    const CLOCK_SLACK_MS = 10 * 60e3;
    const DIGEST_DAYS = 30;
    const KEEP_DAYS = 60;
    const ANNOUNCE_EVERY_MS = 10 * 60e3;
    const ISO = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/;
    const DAY_KEY = /\/(\d{4}-\d\d-\d\d)$/;
    const PAIR_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

    let state = null; // { house: {s, t, k}, dev, cursor, entries: {key: [value, at, dev]}, seen: [], announced, announcedMs, heardMs }

    const load = () => { try { state = JSON.parse(localStorage.getItem(KEY)) || null; } catch (e) { state = null; } };
    const save = () => { try { if (state) localStorage.setItem(KEY, JSON.stringify(state)); else localStorage.removeItem(KEY); } catch (e) { /* ignore */ } };
    load();

    function randomHex(bytes) {
        const a = new Uint8Array(bytes);
        crypto.getRandomValues(a);
        return [...a].map(b => b.toString(16).padStart(2, '0')).join('');
    }

    // ---------- household codes (relay.dart Household.fromCode) ----------
    function cleanServer(s) { return s.trim().replace(/\/+$/, ''); }

    function houseFromJson(raw) {
        if (!raw || typeof raw !== 'object') return null;
        const { s, t, k } = raw;
        if (typeof s !== 'string' || typeof t !== 'string') return null;
        let url;
        try { url = new URL(s); } catch (e) { return null; }
        if (!(url.protocol === 'https:' || url.protocol === 'http:') || !url.hostname) return null;
        if (!/^[A-Za-z0-9_-]{8,64}$/.test(t)) return null;
        const token = typeof k === 'string' && k.trim() ? k.trim() : null;
        return { s: cleanServer(s), t, k: token };
    }

    function houseFromCode(code) {
        const text = String(code || '').replace(/\s+/g, '');
        if (!text) return null;
        try {
            const b64 = text.replace(/-/g, '+').replace(/_/g, '/');
            const padded = b64.padEnd(Math.ceil(b64.length / 4) * 4, '=');
            const bytes = Uint8Array.from(atob(padded), c => c.charCodeAt(0));
            return houseFromJson(JSON.parse(new TextDecoder().decode(bytes)));
        } catch (e) {
            return null;
        }
    }

    const headers = (house) => house.k ? { Authorization: `Bearer ${house.k}` } : {};

    // ---------- entries and digest (sync_core.dart) ----------
    function entryFromWire(raw) {
        if (!Array.isArray(raw) || raw.length !== 4) return null;
        const [k, v, at, dev] = raw;
        if (typeof k !== 'string' || !k || k.length > 80) return null;
        if (!(v === null || typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean')) return null;
        if (typeof v === 'string' && v.length > 400) return null;
        if (typeof at !== 'string' || !ISO.test(at)) return null;
        if (typeof dev !== 'string' || !dev || dev.length > 32) return null;
        return { k, v, at, dev };
    }

    // Newest write wins; a tie goes to the larger device id.
    function beats(a, b) { return a.at > b.at || (a.at === b.at && a.dev > b.dev); }

    const utcDay = (ms) => new Date(ms).toISOString().slice(0, 10);
    function olderThan(key, cutoffDay) { const m = DAY_KEY.exec(key); return !!m && m[1] < cutoffDay; }

    // A fingerprint of the whole state; equal to the phones' when both hold the same facts.
    async function digestOf(entries, nowMs) {
        const cutoff = utcDay(nowMs - DIGEST_DAYS * 864e5);
        const keys = Object.keys(entries).filter(k => !olderThan(k, cutoff)).sort();
        const text = JSON.stringify(keys.map(k => [k, ...entries[k]]));
        const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
        return [...new Uint8Array(hash)].map(b => b.toString(16).padStart(2, '0')).join('').slice(0, 16);
    }
    const digest = () => digestOf(state.entries, Date.now());

    function tidy() {
        const cutoff = utcDay(Date.now() - KEEP_DAYS * 864e5);
        for (const k of Object.keys(state.entries)) if (olderThan(k, cutoff)) delete state.entries[k];
    }

    // Folds one "dp2 ..." line in; true when it changed anything.
    function receive(line) {
        let raw;
        try { raw = JSON.parse(line.slice(WIRE.length)); } catch (e) { return false; }
        if (!raw || typeof raw !== 'object' || typeof raw.d !== 'string' || raw.d === state.dev) return false;
        const latest = new Date(Date.now() + CLOCK_SLACK_MS).toISOString();
        let changed = false;
        for (const item of Array.isArray(raw.s) ? raw.s : []) {
            const e = entryFromWire(item);
            if (!e || e.at > latest) continue;
            const cur = state.entries[e.k];
            if (cur && !beats(e, { at: cur[1], dev: cur[2] })) continue;
            state.entries[e.k] = [e.v, e.at, e.dev];
            changed = true;
        }
        return changed;
    }

    // ---------- relay ----------
    async function pollLines(house, topic, since) {
        const url = `${house.s}/${topic}/json?poll=1&since=${since}`;
        const res = await fetch(url, { headers: headers(house), cache: 'no-store' });
        if (!res.ok) throw new Error(`The relay answered ${res.status}`);
        const out = [];
        for (const row of (await res.text()).split('\n')) {
            let msg;
            try { msg = JSON.parse(row); } catch (e) { continue; }
            if (!msg || msg.event !== 'message' || typeof msg.message !== 'string') continue;
            for (const part of msg.message.split('\n')) out.push({ id: msg.id, time: msg.time, line: part });
        }
        return out;
    }

    async function publish(house, topic, title, body, line) {
        const url = `${house.s}/${topic}?title=${encodeURIComponent(title)}&tags=plate_with_cutlery&priority=1`;
        const res = await fetch(url, {
            method: 'POST', headers: { ...headers(house), 'Content-Type': 'text/plain; charset=utf-8' },
            body: `${body}\n\n${line}`
        });
        return res.ok;
    }

    async function announce(force) {
        const mine = await digest();
        if (!force && mine === state.announced && Date.now() - (state.announcedMs || 0) < ANNOUNCE_EVERY_MS) return;
        const ok = await publish(state.house, state.house.t, 'Kitchen screen checked in', 'The kitchen screen is reading the plan.',
            WIRE + JSON.stringify({ d: state.dev, g: mine, s: [] }));
        if (ok) { state.announced = mine; state.announcedMs = Date.now(); save(); }
    }

    let busy = null;
    // Reads what the phones sent and says what this screen holds. Returns true
    // when the plan changed. `force` re-announces even when nothing changed,
    // which nudges the phones to send everything again.
    function refresh(force) {
        if (!state) return Promise.resolve(false);
        if (busy) return busy;
        busy = (async () => {
            const rows = await pollLines(state.house, state.house.t, state.cursor ? state.cursor - 1 : 'all');
            let changed = false;
            const seen = new Set(state.seen);
            for (const row of rows) {
                if (!row.line.startsWith(WIRE)) continue;
                const key = `${row.id}:${row.line.length}`;
                if (seen.has(key)) continue;
                seen.add(key);
                if (receive(row.line)) changed = true;
                if (typeof row.time === 'number' && row.time > (state.cursor || 0)) state.cursor = row.time;
            }
            state.seen = [...seen].slice(-300);
            state.heardMs = Date.now();
            tidy();
            save();
            await announce(force);
            return changed;
        })().finally(() => { busy = null; });
        return busy;
    }

    async function link(code) {
        const house = houseFromCode(code);
        if (!house) return false;
        state = { house, dev: `show-${randomHex(6)}`, cursor: 0, entries: {}, seen: [], announced: null, announcedMs: 0, heardMs: 0 };
        save();
        try { await refresh(true); } catch (e) { /* stays linked; the next refresh tries again */ }
        return true;
    }

    function unlink() { state = null; save(); }

    // ---------- pairing a screen ----------
    function newPairCode() {
        const a = new Uint8Array(6);
        crypto.getRandomValues(a);
        return [...a].map(b => PAIR_ALPHABET[b % PAIR_ALPHABET.length]).join('');
    }
    const pairTopic = (code) => `dp-pair-${code.toLowerCase()}`;
    const PAIR_SERVER = { s: 'https://ntfy.sh', k: null };

    // Waits for a phone to send a household code to this screen's pairing code.
    // Resolves true once linked, false when `stopped()` says to give up.
    async function waitForPair(code, stopped) {
        const since = Math.floor(Date.now() / 1000) - 5;
        while (!stopped()) {
            try {
                for (const row of await pollLines(PAIR_SERVER, pairTopic(code), since)) {
                    if (row.line.startsWith(PAIR_WIRE) && await link(row.line.slice(PAIR_WIRE.length))) return true;
                }
            } catch (e) { /* try again */ }
            await new Promise(r => setTimeout(r, 3000));
        }
        return false;
    }

    async function sendToScreen(householdCode, screenCode) {
        const code = String(screenCode || '').trim().toUpperCase();
        if (!houseFromCode(householdCode) || !/^[A-Z0-9]{6}$/.test(code)) return false;
        return publish(PAIR_SERVER, pairTopic(code), 'Linking a kitchen screen', 'A household code for a kitchen screen.',
            PAIR_WIRE + String(householdCode).replace(/\s+/g, ''));
    }

    // ---------- reading the plan (plan.dart) ----------
    const localDay = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    function text(key) { const e = state && state.entries[key]; return e && typeof e[0] === 'string' && e[0] ? e[0] : null; }

    // [{day: Date, slug, cook}] for today and the next `days - 1` days that have a dinner.
    function upcoming(days) {
        if (!state) return [];
        const out = [];
        const now = new Date();
        for (let i = 0; i < days; i++) {
            const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
            const key = localDay(day);
            const slug = text(`meal/${key}`);
            if (!slug) continue;
            const who = text(`cook/${key}`);
            out.push({ day, offset: i, slug, cook: who === 'pink' || who === 'blue' ? who : null });
        }
        return out;
    }

    function name(who, fallback) { return text(`name/${who}`) || fallback; }

    // What the household wrote about a recipe on the phones, or null.
    function note(slug) { return text(`note/${slug}`); }

    return {
        linked: () => !!state,
        heardMs: () => (state && state.heardMs) || 0,
        refresh, link, unlink, upcoming, name, note,
        newPairCode, waitForPair, sendToScreen, houseFromCode,
        digestOf
    };
})();
