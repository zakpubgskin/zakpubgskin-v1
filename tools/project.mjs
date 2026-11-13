import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { deflateSync } from 'node:zlib';

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const FILENAMES = { controller: 'PlayerControllerBase.lua', ui: 'ui_util.lua' };
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const json = value => JSON.stringify(value, null, 2) + '\n';
const fail = message => { throw new Error(message); };
const utf8 = bytes => new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);

// Decimal escapes work on Lua 5.1 through 5.5, including UTF-8 strings.
export function luaStringContent(text) {
  return [...Buffer.from(text, 'utf8')].map(byte => {
    if (byte === 34) return '\\"';
    if (byte === 92) return '\\\\';
    if (byte < 32 || byte > 126) return '\\' + String(byte).padStart(3, '0');
    return String.fromCharCode(byte);
  }).join('');
}

export async function readConfig(root = ROOT) {
  return JSON.parse((await readFile(resolve(root, 'project.json'), 'utf8')).replace(/^\uFEFF/, ''));
}

function validate(config) {
  if (config.schema !== 1 || !FILENAMES[config.variant] ||
      config.game_file !== FILENAMES[config.variant]) fail('Invalid variant/game_file. Keep the original game module name.');
  if (typeof config.worker_name !== 'string' ||
      !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(config.worker_name)) fail('worker_name must be a valid workers.dev name (1-63 lowercase letters/digits/dashes).');
  if (typeof config.account_id !== 'string' ||
      (config.account_id && !/^[a-f0-9]{32}$/.test(config.account_id))) fail('account_id must be empty or a 32-character lowercase hexadecimal Cloudflare account ID.');
  if (typeof config.payload_name !== 'string' ||
      !/^[a-z0-9][a-z0-9_-]*\.lua$/.test(config.payload_name)) fail('payload_name must be a lowercase .lua name, without folders.');
  if (typeof config.url !== 'string') fail('url must be an HTTPS Worker root URL.');
  const endpoint = new URL(config.url);
  if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password ||
      endpoint.port || endpoint.pathname !== '/' || endpoint.search || endpoint.hash ||
      endpoint.href !== config.url) fail('url must be a canonical HTTPS root URL ending in /, without credentials, port, query, or fragment.');
  if (endpoint.hostname.endsWith('.workers.dev') &&
      (endpoint.hostname.split('.').length !== 4 || endpoint.hostname.split('.')[0] !== config.worker_name)) {
    fail('The Worker name and workers.dev URL do not match. Use the account workers.dev subdomain, not the GitHub username.');
  }
  if (typeof config.marker !== 'string' || !config.marker ||
      Buffer.byteLength(config.marker) > 256 || /[\r\n\0]/.test(config.marker)) fail('marker must be a nonempty single-line prefix, at most 256 UTF-8 bytes.');
  if (!Number.isSafeInteger(config.original_bytes) || config.original_bytes < 1) fail('Invalid original byte limit.');
  for (let level = 1; level <= 9; level++) {
    if (!Number.isSafeInteger(config.original_zlib?.[level]) || config.original_zlib[level] < 1) fail('Missing original compressed size baseline.');
  }
}

export async function plan(root = ROOT, config) {
  config ??= await readConfig(root);
  validate(config);
  const payload = await readFile(resolve(root, 'online/2.lua'));
  const payloadText = utf8(payload);
  if (payload.subarray(0, 3).equals(Buffer.from([239, 187, 191]))) fail('Save online/2.lua as UTF-8 without a BOM.');
  if (!payloadText.startsWith(config.marker)) fail('online/2.lua does not begin with project.json marker.');
  const digest = sha256(payload);
  const manifest = { version: 'sha256-' + digest.slice(0, 12), sha256: digest, bytes: payload.length };
  let core = (await readFile(resolve(root, 'src/online_entry.lua'), 'utf8')).replace(/\r\n/g, '\n');
  const replacements = {
    __LOCAL_RELEASE_URL__: luaStringContent(config.url),
    __LOCAL_RELEASE_LENGTH__: String(payload.length),
    __LOCAL_RELEASE_ID__: digest,
    __LOCAL_RELEASE_MARKER__: luaStringContent(config.marker),
    __LOCAL_REQUEST_BODY__: luaStringContent('key_path=' + config.payload_name),
  };
  for (const [token, value] of Object.entries(replacements)) {
    if (core.split(token).length !== 2) fail('Missing or duplicate Lua template token: ' + token);
    core = core.replace(token, () => value);
  }
  const native = await readFile(resolve(root, 'src/native.lua'));
  const recovery = await readFile(resolve(root, 'src/native_recovery.lua'));
  const game = Buffer.concat([
    Buffer.from('-- Independent entry: native module first, then in-game online startup.\nlocal originalExport = (function()\n'),
    native, Buffer.from('\nend)()\n\n'), recovery,
    Buffer.from('\n' + core + '\nreturn originalExport\n'),
  ]);
  if (game.length >= config.original_bytes) fail(`Game Lua is ${game.length} bytes; it must stay below ${config.original_bytes}. Shorten the Worker URL/name or review source size; no whitespace or gameplay code was removed automatically.`);
  const zlib = Object.fromEntries(Array.from({ length: 9 }, (_, index) => {
    const level = index + 1;
    const output = deflateSync(game, { level }).length;
    return [level, { original: config.original_zlib[level], output, fits_original: output < config.original_zlib[level] }];
  }));
  const report = {
    game_file: config.game_file, output_bytes: game.length, original_bytes: config.original_bytes,
    raw_bytes_saved: config.original_bytes - game.length, output_sha256: sha256(game),
    payload_bytes: payload.length, payload_sha256: digest, zlib,
    fits_original_compressed_all_levels: Object.values(zlib).every(item => item.fits_original),
    game_runtime_tested: false, pak_encryption_tested: false,
  };
  const wrangler = {
    $schema: 'node_modules/wrangler/config-schema.json',
    name: config.worker_name,
    ...(config.account_id ? { account_id: config.account_id } : {}),
    main: 'cloudflare/worker.mjs', compatibility_date: '2026-10-19',
    workers_dev: true, preview_urls: false, send_metrics: false,
    rules: [{ type: 'Text', globs: ['**/*.lua'], fallthrough: true }],
  };
  const worker = "import payload from '../online/2.lua';\nimport { manifest } from './release-manifest.mjs';\nimport { createHandler } from './handler.mjs';\n\nexport default {\n  fetch: createHandler({ payload, manifest, primaryName: " + JSON.stringify(config.payload_name) + " }),\n};\n";
  return { config, game, payload, payloadText, manifest, report, outputs: new Map([
    ['game/' + config.game_file, game],
    ['cloudflare/worker.mjs', Buffer.from(worker)],
    ['cloudflare/release-manifest.mjs', Buffer.from('export const manifest = ' + json(manifest).trimEnd() + ';\n')],
    ['wrangler.json', Buffer.from(json(wrangler))],
    ['SIZE_REPORT.json', Buffer.from(json(report))],
  ]) };
}

export async function build(root = ROOT, { config, check = false } = {}) {
  const result = await plan(root, config);
  for (const [name, bytes] of result.outputs) {
    const target = resolve(root, name);
    if (check) {
      if (!(await readFile(target)).equals(bytes)) fail('Generated file is stale: ' + name + '. Run npm run build.');
    } else {
      await mkdir(dirname(target), { recursive: true });
      await writeFile(target, bytes);
    }
  }
  return result;
}

export async function configure(root, args) {
  const config = await readConfig(root);
  const fields = { '--worker-name': 'worker_name', '--account-id': 'account_id', '--url': 'url', '--payload-name': 'payload_name' };
  if (!args.length || args.length % 2) fail('Use --worker-name NAME --account-id ID --url https://NAME.SUBDOMAIN.workers.dev/ [--payload-name main.lua].');
  const seen = new Set();
  for (let index = 0; index < args.length; index += 2) {
    const flag = args[index];
    if (!fields[flag] || seen.has(flag) || args[index + 1].startsWith('--')) fail('Unknown, duplicate, or missing configure option: ' + flag);
    seen.add(flag);
    config[fields[flag]] = args[index + 1];
  }
  await plan(root, config); // Validate all inputs and size before changing any file.
  await writeFile(resolve(root, 'project.json'), json(config));
  return build(root, { config });
}

export function validateDeployment(config, env = process.env) {
  if (!config.account_id) fail('Set your own Cloudflare account_id with npm run configure before deployment.');
  for (const key of ['CLOUDFLARE_ACCOUNT_ID', 'CF_ACCOUNT_ID']) {
    if (env[key] && env[key] !== config.account_id) fail(key + ' differs from project.json account_id.');
  }
}

async function wrangler(root, result, dryRun) {
  if (!dryRun) validateDeployment(result.config);
  const executable = resolve(root, 'node_modules/wrangler/bin/wrangler.js');
  await access(executable).catch(() => fail('Wrangler is not installed. Run npm ci first.'));
  const args = ['deploy', '--config', 'wrangler.json'];
  if (dryRun) args.push('--dry-run', '--outdir', '.build/worker');
  const child = spawnSync(process.execPath, [executable, ...args], {
    cwd: root, stdio: 'inherit', shell: false,
    env: { ...process.env, WRANGLER_SEND_METRICS: 'false',
      ...(result.config.account_id ? { CLOUDFLARE_ACCOUNT_ID: result.config.account_id } : {}) },
  });
  if (child.error) throw child.error;
  if (child.status !== 0) fail('Wrangler failed with exit status ' + child.status);
}

export async function verifyOnline(result) {
  const response = await fetch(result.config.url, {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(30000),
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': 'SourceVerification/1.0' },
    body: 'key_path=' + result.config.payload_name,
  });
  if (!response.ok) fail('Worker returned HTTP ' + response.status + '. Response content was not printed.');
  const downloaded = Buffer.from(await response.arrayBuffer());
  if (downloaded.length !== result.manifest.bytes || sha256(downloaded) !== result.manifest.sha256) {
    fail('Online payload does not match this source. Check the deployed account, URL and payload.');
  }
  console.log('PASS: online payload length and SHA256 match; Lua was not executed.');
}

async function main(args) {
  const [command = 'build', ...rest] = args;
  if (!['build', 'check', 'configure', 'dry-run', 'deploy', 'verify-online'].includes(command)) fail('Unknown command: ' + command);
  if (command !== 'configure' && rest.length) fail('Unexpected command arguments.');
  const result = command === 'configure' ? await configure(ROOT, rest)
    : await build(ROOT, { check: command === 'check' || command === 'verify-online' });
  console.log(`PASS: ${result.config.game_file}, ${result.game.length}/${result.config.original_bytes} raw bytes. Payload: ${result.manifest.bytes} bytes.`);
  console.log('Fits original zlib sizes at all levels: ' + result.report.fits_original_compressed_all_levels);
  if (command === 'dry-run' || command === 'deploy') await wrangler(ROOT, result, command === 'dry-run');
  if (command === 'verify-online') await verifyOnline(result);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(error => {
    console.error('ERROR: ' + error.message);
    process.exitCode = 1;
  });
}
