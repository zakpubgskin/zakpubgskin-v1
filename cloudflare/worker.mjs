import payload from "../online/2.lua";
import { createHandler } from "./handler.mjs";

export default {
  fetch: createHandler({ payload, primaryName: "2.lua" }),
};
