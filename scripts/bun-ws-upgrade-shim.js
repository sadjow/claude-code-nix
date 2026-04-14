// Workaround for a bun runtime bug that breaks /voice in claude-bun.
//
// Root cause: bun's http/https client emits a 'response' event for HTTP 101
// Switching Protocols responses, where node emits 'upgrade'. The `ws` npm
// package (bundled into claude-code's cli.js) listens for 'upgrade' and treats
// a 'response' as a failed handshake, emits 'unexpected-response' with status
// 101, and the voice_stream WebSocket never reaches the OPEN state. /voice
// then fails silently with "Voice connection failed. Check your network and
// try again."
//
// This preload monkey-patches http.request / https.request so that 101
// responses are re-emitted as 'upgrade' events, matching node's behaviour.
// We synthesize a duplex-ish socket that reads from the response stream
// (where bun delivers the post-handshake bytes) and writes to the underlying
// net/tls socket.

const http = require('http');
const https = require('https');
const { EventEmitter } = require('events');

function buildFakeSocket(res) {
  const fake = new EventEmitter();
  fake.readable = true;
  fake.writable = true;
  fake.destroyed = false;
  fake.setTimeout = () => {};
  fake.setNoDelay = () => {};
  fake.setKeepAlive = () => {};
  fake.pause = () => { try { res.pause(); } catch {} };
  fake.resume = () => { try { res.resume(); } catch {} };
  fake.write = (chunk, encOrCb, cb) => res.socket.write(chunk, encOrCb, cb);
  fake.end = (...args) => res.socket.end(...args);
  fake.destroy = (...args) => {
    fake.destroyed = true;
    return res.socket.destroy(...args);
  };
  fake.cork = () => res.socket.cork && res.socket.cork();
  fake.uncork = () => res.socket.uncork && res.socket.uncork();
  // Proxy readable-side events from res, where bun delivers the raw frame bytes.
  res.on('data', (d) => fake.emit('data', d));
  res.on('end', () => fake.emit('end'));
  res.on('close', () => fake.emit('close'));
  res.on('error', (e) => fake.emit('error', e));
  return fake;
}

function patch(mod) {
  const orig = mod.request;
  mod.request = function patchedRequest(...args) {
    const req = orig.apply(this, args);
    req.prependListener('response', (res) => {
      if (res.statusCode !== 101) return;
      const fake = buildFakeSocket(res);
      // Suppress the 'unexpected-response' path that ws would otherwise take.
      req.removeAllListeners('response');
      req.emit('upgrade', res, fake, Buffer.alloc(0));
    });
    return req;
  };
}

patch(http);
patch(https);
