// PeerJS signaling server for Catch the Thief. It only introduces players to each other (no game data passes through it).
const { PeerServer } = require('peer');
const port = +process.env.PORT || 9000;
const server = PeerServer({
  port,
  path: '/',
  proxied: true,                 // behind Render / Cloudflare / nginx
  allow_discovery: false,        // nobody can list connected peers
  concurrent_limit: +process.env.MAX_PEERS || 5000,   // per process; run several instances behind a load balancer
  alive_timeout: 60000,
  key: process.env.PEER_KEY || 'peerjs',
  corsOptions: { origin: (process.env.ALLOWED_ORIGINS || '*').split(',') }
});
server.on('connection', c => { if (process.env.DEBUG) console.log('+', c.getId()); });
server.on('disconnect', c => { if (process.env.DEBUG) console.log('-', c.getId()); });
console.log('PeerServer listening on', port);
