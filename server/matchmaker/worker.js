/* Catch the Thief: public-room matchmaker (Cloudflare Worker + Durable Object).
   Instead of every player probing slots 1..12 through the PeerJS broker, the client asks this service
   "which room should I join?" and gets a short list of slot numbers to try. Hosts send a heartbeat every
   few seconds with their player count; rooms that stop sending are forgotten.
   State is in memory only (a lost room just means players get a fresh one), so nothing personal is stored. */
const MAX = 8;            // players per room (keep equal to TV_ROOM_MAX in the game)
const TTL = 16000;        // ms without a heartbeat before a room is dropped
const GRACE = 20000;      // ms a freshly assigned slot is kept while its host starts up
const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-methods': 'GET,POST,OPTIONS',
  'access-control-allow-headers': 'content-type', 'cache-control': 'no-store' };
const json = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'content-type': 'application/json' } });
const KEY = /^pub-[a-z0-9]{1,12}$/i;

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
    const u = new URL(req.url);
    if (u.pathname === '/health') return json({ ok: true });
    if (!['/assign', '/hb', '/leave'].includes(u.pathname)) return json({ error: 'not found' }, 404);
    const k = u.searchParams.get('k') || '';
    const sh = Math.min(Math.max(parseInt(u.searchParams.get('sh') || '0', 10) || 0, 0), 63);
    if (!KEY.test(k)) return json({ error: 'bad key' }, 400);
    const stub = env.LOBBY.get(env.LOBBY.idFromName(k.toLowerCase() + ':' + sh));
    return stub.fetch(req);
  }
};

export class Lobby {
  constructor() { this.rooms = new Map(); }   // slot -> {n, busy, ts}
  prune(now) { for (const [s, r] of this.rooms) if (now - r.ts > (r.fresh ? GRACE : TTL)) this.rooms.delete(s); }
  async fetch(req) {
    const u = new URL(req.url), now = Date.now();
    this.prune(now);
    if (u.pathname === '/assign') {
      // only rooms whose host has already sent a heartbeat are joinable; a bare reservation (fresh) has no host yet
      const open = [...this.rooms].filter(([, r]) => !r.fresh && !r.busy && r.n < MAX).sort((a, b) => b[1].n - a[1].n).slice(0, 3);
      const slots = open.map(([s]) => s);
      let fresh = 1; while (this.rooms.has(fresh)) fresh++;
      // reserve a seat so a burst of players does not all get the same room
      for (const [s, r] of open.slice(0, 1)) r.n++;
      this.rooms.set(fresh, { n: 0, busy: false, ts: now, fresh: true });
      return json({ slots: [...slots, fresh], rooms: this.rooms.size });
    }
    const slot = parseInt(u.searchParams.get('s') || '', 10);
    if (!(slot >= 1 && slot <= 100000)) return json({ error: 'bad slot' }, 400);
    if (u.pathname === '/leave') { this.rooms.delete(slot); return json({ ok: true }); }
    const n = Math.min(Math.max(parseInt(u.searchParams.get('n') || '1', 10) || 1, 0), MAX);
    this.rooms.set(slot, { n, busy: u.searchParams.get('b') === '1', ts: now, fresh: false });
    return json({ ok: true });
  }
}
