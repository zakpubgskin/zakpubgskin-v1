import payload from "../online/2.lua";
import { createHandler } from "./handler.mjs";

var worker_default = {
  fetch: createHandler({ payload, manifest, primaryName: "2.lua" })
};
