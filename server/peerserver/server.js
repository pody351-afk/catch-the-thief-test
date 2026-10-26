// PeerJS signaling server for Catch the Thief. It only introduces players to each other (no game data passes through it).
const { PeerServer } = require('peer');
const port = +process.env.PORT || 9000;
// ALLOWED_ORIGINS: comma separated list, or empty / "*" to allow every origin (the cors package does not treat ['*'] as a wildcard)
const origins = (process.env.ALLOWED_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean);
const server = PeerServer({
  port,
  path: '/',
  proxied: true,                 // behind Render / Cloudflare / nginx
  allow_discovery: false,        // nobody can list connected peers
  concurrent_limit: +process.env.MAX_PEERS || 5000,   // per process; run several instances behind a load balancer
  alive_timeout: 60000,
  // How long the server holds a connection request for a peer that is not online before answering "peer-unavailable".
  // Default is 5000. A shorter wait makes joining a room whose host just left much faster; online peers answer instantly.
  expire_timeout: +process.env.EXPIRE_MS || 1500,
  key: process.env.PEER_KEY || 'peerjs',
  corsOptions: { origin: (origins.length && !origins.includes('*')) ? origins : true }
});
server.on('connection', c => { if (process.env.DEBUG) console.log('+', c.getId()); });
server.on('disconnect', c => { if (process.env.DEBUG) console.log('-', c.getId()); });
console.log('PeerServer listening on', port);
