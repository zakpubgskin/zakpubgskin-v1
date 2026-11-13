import payload from '../online/2.lua';
import { manifest } from './release-manifest.mjs';
import { createHandler } from './handler.mjs';

export default {
  fetch: createHandler({ payload, manifest, primaryName: "2.lua" }),
};
