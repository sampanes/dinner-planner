// Sync for a static site: changes made on a device (ratings, "we cooked this",
// the week's plan) are queued in localStorage, shown on this device at once, and
// sent as a push message to the ntfy.sh topic in data/source/kitchen.json.
// scripts/pull_changes.py (run hourly by .github/workflows/sync.yml) folds them
// into data/source/*.json, so every device sees them after the next Pages deploy.
// A queued change is re-sent every few hours until the committed files show it,
// because ntfy.sh only keeps messages for about 12 hours.
'use strict';

const Sync = (() => {
    const KEY = 'dp.pending';
    const RESEND_MS = 4 * 3600e3;
    let config = { ntfyTopic: '', people: { pink: 'Pink', blue: 'Blue' } };
    let log = { plan: null, cooked: [], rated: {} };
    let names = {};

    const read = () => { try { return JSON.parse(localStorage.getItem(KEY)) || []; } catch (e) { return []; } };
    const write = (list) => { try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) { /* ignore */ } };
    const newId = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);

    async function getJson(url) {
        try { const res = await fetch(url, { cache: 'no-cache' }); return res.ok ? await res.json() : null; }
        catch (e) { return null; }
    }

    // recipeNames: { slug: display name }, used only for the push message text.
    async function load(recipeNames) {
        names = recipeNames || {};
        const [c, l] = await Promise.all([getJson('data/source/kitchen.json'), getJson('data/source/log.json')]);
        if (c) config = { ...config, ...c, people: { ...config.people, ...(c.people || {}) } };
        if (l) log = { plan: l.plan || null, cooked: l.cooked || [], rated: l.rated || {} };
        write(read().filter(ev => !landed(ev)));
        flush();
    }

    function landed(ev) {
        if (ev.k === 'rate') { const at = (log.rated[ev.slug] || {})[ev.who]; return !!at && at >= ev.at; }
        if (ev.k === 'cooked') return log.cooked.some(c => c.id === ev.id);
        if (ev.k === 'plan') return !!log.plan && log.plan.at >= ev.at;
        return true;
    }

    function queue(fields) {
        const ev = { ...fields, id: newId(), at: new Date().toISOString().replace(/\.\d+Z$/, 'Z') };
        const list = read();
        list.push(ev);
        write(list);
        send(ev);
        return ev;
    }

    function headline(ev) {
        const name = names[ev.slug] || ev.slug;
        if (ev.k === 'rate') return [`${config.people[ev.who] || ev.who}: ${ev.stars} star${ev.stars === 1 ? '' : 's'}`, name];
        if (ev.k === 'cooked') return ['Cooked tonight', name];
        if (ev.k === 'plan') return [`New plan: ${ev.slugs.length} meals`, ev.slugs.map(s => names[s] || s).join(', ')];
        return ['Dinner planner', ''];
    }

    async function send(ev) {
        if (!config.ntfyTopic) return;
        const [title, body] = headline(ev);
        const { sentAt, ...payload } = ev;
        // A plain-text POST with the title as a query parameter is a "simple"
        // request: no CORS preflight, which keeps old browsers (the Show's Silk) happy.
        const url = `https://ntfy.sh/${encodeURIComponent(config.ntfyTopic)}?title=${encodeURIComponent(title)}&tags=plate_with_cutlery`;
        try {
            const res = await fetch(url, { method: 'POST', body: `${body}\n\ndp1 ${JSON.stringify(payload)}` });
            if (!res.ok) return;
            write(read().map(x => x.id === ev.id ? { ...x, sentAt: Date.now() } : x));
        } catch (e) { /* offline: flush() tries again later */ }
    }

    function flush() {
        for (const ev of read()) if (!ev.sentAt || Date.now() - ev.sentAt > RESEND_MS) send(ev);
    }
    setInterval(flush, 10 * 60e3);
    window.addEventListener('online', flush);

    // ---- views: committed state with this device's unsent changes on top ----
    function stars(slug, base) {
        const out = { pink: (base && base.pink) || 0, blue: (base && base.blue) || 0 };
        for (const ev of read()) if (ev.k === 'rate' && ev.slug === slug) out[ev.who] = ev.stars;
        return out;
    }

    function history(slug) {
        const dates = log.cooked.filter(c => c.slug === slug).map(c => c.at);
        for (const ev of read()) if (ev.k === 'cooked' && ev.slug === slug) dates.push(ev.at);
        dates.sort();
        return { count: dates.length, last: dates.length ? dates[dates.length - 1] : null };
    }

    function plan() {
        let best = log.plan;
        for (const ev of read()) if (ev.k === 'plan' && (!best || ev.at > best.at)) best = ev;
        return best;
    }

    return {
        load, queue, stars, history, plan,
        people: () => config.people,
        pending: () => read().length
    };
})();
