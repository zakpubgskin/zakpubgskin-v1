import assert from 'node:assert/strict';
import { build, ROOT } from './project.mjs';
import { createHandler } from '../cloudflare/handler.mjs';

// HTTP is entirely in memory. The private Lua is compared as inert text.
const result = await build(ROOT, { check: true });
const fetch = createHandler({ payload: result.payloadText, manifest: result.manifest, primaryName: result.config.payload_name });
const origin = 'https://offline.invalid';
const post = body => new Request(origin + '/', {
  method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body,
});
const response = await fetch(post('key_path=' + result.config.payload_name));
assert.equal(response.status, 200);
assert.deepEqual(Buffer.from(await response.arrayBuffer()), result.payload);
assert.equal(response.headers.get('X-Content-SHA256'), result.manifest.sha256);
const direct = await fetch(new Request(origin + '/' + result.config.payload_name));
assert.equal(direct.status, 200);
assert.deepEqual(Buffer.from(await direct.arrayBuffer()), result.payload);
const health = await fetch(new Request(origin + '/health'));
assert.equal(health.status, 200);
assert.deepEqual(await health.json(), { ok: true, ...result.manifest });
const absent = result.config.payload_name === 'missing.lua' ? 'missing_other.lua' : 'missing.lua';
assert.equal((await fetch(post('key_path=' + absent))).status, 404);
assert.equal((await fetch(post('key_path=' + result.config.payload_name + '&key_path=' + absent))).status, 400);
assert.equal((await fetch(new Request(origin + '/', { method: 'OPTIONS' }))).status, 204);
assert.equal((await fetch(new Request(origin + '/health', { method: 'PUT' }))).status, 405);
console.log('PASS: reproducible build, payload bytes, POST/GET/health and error responses. No network; no Lua execution.');
