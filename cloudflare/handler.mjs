const MAX_FORM_BYTES = 1024;
const COMMON_HEADERS = Object.freeze({
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Expose-Headers": "X-Content-SHA256",
  "Cache-Control": "no-store, max-age=0",
  "X-Content-Type-Options": "nosniff",
});

class RequestError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function response(body, status = 200, extraHeaders = {}) {
  return new Response(body, {
    status,
    headers: {
      ...COMMON_HEADERS,
      "Content-Type": "text/plain; charset=utf-8",
      ...extraHeaders,
    },
  });
}

async function readForm(request) {
  const contentType = (request.headers.get("Content-Type") || "")
    .split(";", 1)[0].trim().toLowerCase();
  if (contentType !== "application/x-www-form-urlencoded") {
    throw new RequestError(400, "Expected form data");
  }
  const contentLength = request.headers.get("Content-Length");
  if (contentLength !== null) {
    if (!/^\d+$/.test(contentLength)) {
      throw new RequestError(400, "Invalid request length");
    }
    if (Number(contentLength) > MAX_FORM_BYTES) {
      throw new RequestError(413, "Request too large");
    }
  }

  let text = "";
  let size = 0;
  if (request.body) {
    const reader = request.body.getReader();
    const decoder = new TextDecoder("utf-8", { fatal: true });
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_FORM_BYTES) {
          await reader.cancel().catch(() => {});
          throw new RequestError(413, "Request too large");
        }
        text += decoder.decode(value, { stream: true });
      }
      text += decoder.decode();
    } catch (error) {
      if (error instanceof RequestError) throw error;
      throw new RequestError(400, "Invalid request body");
    } finally {
      reader.releaseLock();
    }
  }

  const form = new URLSearchParams(text);
  if (form.getAll("key_path").length !== 1 ||
      [...form.keys()].some((key) => key !== "key_path")) {
    throw new RequestError(400, "Expected one key_path");
  }
  return form.get("key_path");
}

export function createHandler({ payload, manifest, primaryName = "1.lua", releases = {} }) {
  function release(body, metadata) {
  if (typeof body !== "string" || !metadata ||
      typeof metadata.version !== "string" || !metadata.version ||
      !/^[a-f0-9]{64}$/.test(metadata.sha256 || "") ||
      !Number.isSafeInteger(metadata.bytes) || metadata.bytes < 1 ||
      new TextEncoder().encode(body).byteLength !== metadata.bytes) {
    throw new TypeError("Invalid bundled release");
  }
  return Object.freeze({payload: body, manifest: Object.freeze({version: metadata.version, sha256: metadata.sha256, bytes: metadata.bytes})});
  }
  const validName = name => typeof name === "string" && /^[a-z0-9][a-z0-9_-]*\.lua$/.test(name);
  if (!validName(primaryName) || !releases || typeof releases !== "object" || Array.isArray(releases)) {
    throw new TypeError("Invalid release map");
  }
  const current = release(payload, manifest);
  const published = new Map([[primaryName, current]]);
  for (const [name, value] of Object.entries(releases)) {
    if (!validName(name) || published.has(name) || !value) throw new TypeError("Invalid release map");
    published.set(name, release(value.payload, value.manifest));
  }
  const health = JSON.stringify({
    ok: true,
    ...current.manifest,
  });

  return async function fetch(request) {
    try {
      const path = new URL(request.url).pathname;
      const selected = published.get(path.slice(1));
      if (path !== "/" && !selected && path !== "/health") {
        return response("Not found", 404);
      }
      const method = request.method.toUpperCase();
      if (method === "OPTIONS") {
        return response(null, 204);
      }
      if (method === "GET") {
        if (path === "/health") {
          return response(health, 200, {
            "Content-Type": "application/json; charset=utf-8",
          });
        }
        if (selected) {
          return response(selected.payload, 200, { "X-Content-SHA256": selected.manifest.sha256 });
        }
        return response("Not found", 404);
      }
      if (method === "POST" && path === "/") {
        const file = await readForm(request);
        const target = published.get(file);
        if (!target) return response("Not found", 404);
        return response(target.payload, 200, { "X-Content-SHA256": target.manifest.sha256 });
      }
      return response("Method not allowed", 405, {
        Allow: path === "/" ? "POST, OPTIONS" : "GET, OPTIONS",
      });
    } catch (error) {
      if (error instanceof RequestError) {
        return response(error.message, error.status);
      }
      return response("Internal error", 500);
    }
  };
}
