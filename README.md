# PlayerControllerBase.lua — সম্পূর্ণ portable source

এই folder-টিই একটি সম্পূর্ণ GitHub project। এতে গেমের PlayerControllerBase.lua, online Lua,
Cloudflare Worker এবং এগুলো পুনরায় তৈরির প্রয়োজনীয় source আছে। অন্য ZIP লাগবে না।
GitHub-এ source রাখা হয়; গেম Lua ডাউনলোড করে Cloudflare Worker থেকে। Worker চালানোর
সময় GitHub login/token লাগে না।

## এখনকার Worker দিয়ে চালানো

`game/PlayerControllerBase.lua` গেমের একই নাম ও একই PAK path-এর ফাইলের জায়গায় বসাতে হবে।
এটি আগের Worker URL দিয়ে তৈরি করা আছে। এই ক্ষেত্রে deploy বা config পরিবর্তন লাগবে না।
PAK encryption/repacking tool এই ZIP-এর অংশ নয়।

## প্রয়োজনীয় ফাইল

| ফাইল | কাজ |
| --- | --- |
| `game/PlayerControllerBase.lua` | তৈরি করা গেমের Lua |
| `src/native.lua` | এই game module-এর আগের প্রস্তুত করা native অংশ |
| `src/native_recovery.lua` | আগের native hook মেরামতের অংশ |
| `src/online_entry.lua` | online loader-এর template |
| `online/2.lua` | বর্তমান আসল online payload; একটিমাত্র copy |
| `cloudflare/handler.mjs` | উদ্ধার করা আসল HTTP handler |
| `cloudflare/worker.mjs`, `release-manifest.mjs` | build থেকে তৈরি Worker entry ও payload metadata |
| `project.json` | Worker নাম, account ID, URL ও download নামের এক জায়গার config |
| `wrangler.json` | build থেকে তৈরি Cloudflare deploy config |
| `package.json`, `package-lock.json` | build/deploy commands ও নির্দিষ্ট Wrangler dependency |
| `tools/` | configure, build, local verification ও deploy চালায় |
| `.gitignore`, `.gitattributes` | local credentials/cache বাদ দেয়; Lua bytes অপরিবর্তিত রাখে |
| `SIZE_REPORT.json` | raw এবং zlib size-এর ফলাফল |

পুরোনো BR bootstrap, nested project.zip, original/reference backups, duplicate
GitHub snapshots, legacy 1.lua এবং unused candidate payload বাদ দেওয়া হয়েছে।
এটি আসল source থেকে সাজানো নতুন portable project; পুরোনো repository-এর অপরিবর্তিত
archive নয়। `online/2.lua` এবং HTTP handler-এর bytes সংরক্ষিত আছে।

## অন্য Cloudflare account / অন্য Worker নামে বানানো

Node.js 24 বা পরের compatible version এবং npm লাগবে। ZIP extract করে এই folder-এ
terminal খুলুন। নিচের placeholder-গুলোর জায়গায় নিজের তথ্য বসাবেন; example account ID
বা URL বাস্তব account-এর তথ্য নয়।

1. নতুন Cloudflare account-এর Account ID ও workers.dev subdomain সংগ্রহ করুন।
   Worker-এর জন্য একটি নাম বেছে নিন, যেমন `my-controller` বা `my-ui`।
   workers.dev subdomain হলো Cloudflare account-এর subdomain; GitHub username নয়।
2. একটি command-এ config ও game Lua নতুন করে তৈরি করুন:

   ```powershell
   npm run configure -- --worker-name YOUR_WORKER_NAME --account-id YOUR_32_HEX_ACCOUNT_ID --url https://YOUR_WORKER_NAME.YOUR_SUBDOMAIN.workers.dev/
   ```

3. local verification এবং deploy tooling ইনস্টল করুন:

   ```powershell
   npm run check
   npm ci
   npm run dry-run
   ```

4. terminal থেকে deploy করতে সঠিক Cloudflare account-এ login করুন:

   ```powershell
   npx wrangler login
   npx wrangler whoami
   npm run deploy
   npm run verify-online
   ```

   login browser-এ সঠিক account বেছে নিন; `whoami` দিয়ে মিলিয়ে নিন।
   `npm run deploy` configured account-এ Worker প্রকাশ করে। অন্য commands-এর মধ্যে
   `verify-online` শুধু configured Worker থেকে Lua এনে bytes/SHA256 মেলায়; চালায় না।
   account_id খালি থাকলে deploy script আগে নিজের account সেট করতে বলে।
5. নতুন করে তৈরি `game/PlayerControllerBase.lua` PAK-এ বসিয়ে গেম সম্পূর্ণ বন্ধ করে আবার চালান।
   পুরোনো game Lua-তে পুরোনো URL থাকে; Worker account পাল্টালেই তা নিজে বদলায় না।

নিজের custom domain আগে থেকেই Worker-এ যুক্ত থাকলে সেটির HTTPS root URL-ও দেওয়া
যাবে। এই project custom-domain DNS/route নিজে তৈরি করে না।

## অন্য GitHub account বা repository-তে রাখা ও Cloudflare থেকে build

1. উপরের configure ও local build/check শেষ করুন।
2. নিজের নির্বাচিত GitHub account-এ একটি **Private** repository তৈরি করুন।
3. এই folder-এর ফাইলগুলো repository root-এ দিন—ZIP ফাইল হিসেবে নয়।
   `package.json`, `project.json` ও `wrangler.json` root-এই থাকবে।
   `.gitignore` ও `.gitattributes`-ও রাখবেন।
4. নতুন Cloudflare account-এর Workers Git integration-এ সেই repository সংযুক্ত করুন।
   Worker-এর নাম `project.json`-এর `worker_name`-এর সঙ্গে মিলিয়ে দিন।
5. Root directory repository root; Build command `npm run build`;
   Deploy command `npm run deploy`; production branch নিজের branch।
   Build environment-এ Node.js 24 ব্যবহার করুন।
6. Deploy শেষে নিজের PC-তে `npm run verify-online` চালিয়ে নতুন URL যাচাই করুন।

GitHub account বা repository-এর নাম বদলালে Lua code-এ GitHub URL বসাতে হয় না।
শুধু নতুন Cloudflare-এ GitHub connection নির্বাচন করতে হবে। একই backend চাইলে
দুটি variant একই Worker ব্যবহার করতে পারে; আলাদা hosting চাইলে আলাদা Worker নাম
ও URL দিয়ে প্রতিটি ZIP-এর project আলাদাভাবে configure করুন।

## online Lua-এর download নাম বা contents বদলানো

download নাম যেমন `2.lua` থেকে `main.lua` করতে:

```powershell
npm run configure -- --payload-name main.lua
npm run check
```

এটি game request-এর `key_path` এবং Worker-এর download নাম একই সঙ্গে বদলায়। Local
source file `online/2.lua`-ই থাকবে। এরপর Worker deploy এবং নতুন game Lua প্রতিস্থাপন
করে গেম restart করতে হবে।

payload code বদলাতে `online/2.lua` edit করুন; UTF-8 without BOM রাখুন। প্রথম prefix
বদলালে `project.json`-এর `marker`-ও মিলিয়ে দিন। তারপর:

```powershell
npm run build
npm run check
npm run deploy
npm run verify-online
```

Build payload-এর byte count, SHA256, server manifest এবং game loader-এর metadata
একই সঙ্গে নতুন করে তৈরি করে। তৈরি `game/PlayerControllerBase.lua` আবার PAK-এ বসাতে হবে।
`game/`, `cloudflare/worker.mjs`, `release-manifest.mjs`, `wrangler.json` সরাসরি edit
করবেন না; পরের build-এ এগুলো আবার তৈরি হবে। Config-এর endpoint পরিবর্তনের জায়গা
`project.json`; source পরিবর্তনের জায়গা `src/`।

## কোন নাম পাল্টানো যাবে

GitHub repository, project folder, Cloudflare Worker এবং payload download নাম
পাল্টানো যায়। গেমের `PlayerControllerBase.lua` নাম/path engine-এর module lookup-এর অংশ—শুধু
rename করলে engine নতুন ফাইলটি লোড করবে এমন নিশ্চয়তা নেই। এই project সেই আসল
module নামই রেখে তৈরি করে।

## যাচাইয়ের সীমা ও size

Default game Lua আগের পরীক্ষিত source package-এর সঙ্গে byte-for-byte একই।
Local checks reproducible build, payload consistency এবং in-memory Worker HTTP
responses যাচাই করে; গোপন online Lua execute করে না। Game/device এবং PAK encryption
এখানে পরীক্ষা করা হয়নি। Raw Lua original-এর চেয়ে ছোট; বর্তমান zlib compressed
size original-এর চেয়ে বড়। `SIZE_REPORT.json`-এ সঠিক সংখ্যা আছে। লম্বা Worker URL
দিলে raw cap ছাড়িয়ে গেলে build স্পষ্ট error দেবে; code minify বা gameplay code
স্বয়ংক্রিয়ভাবে কেটে size মেলাবে না।

## Source ও setup references

- Original repository: https://github.com/masterahsanyt2021/masterahsan-lua-hosting
  (commit `df6f50985a030762f9a7489d502af6d75350234e`); live Cloudflare export থেকে বর্তমান
  handler/payload মিলিয়ে নেওয়া হয়েছে। নতুন configure/build tooling এই package-এর জন্য তৈরি।
- Cloudflare config: https://developers.cloudflare.com/workers/wrangler/configuration/
- Cloudflare Git build settings: https://developers.cloudflare.com/workers/ci-cd/builds/configuration/
- Wrangler commands: https://developers.cloudflare.com/workers/wrangler/commands/

কোনো GitHub/Cloudflare login token এই package-এ নেই। Build/deploy করার সময় নিজের
account connection ব্যবহার হবে। Online Lua-সহ এই source private repository-তেই রাখুন।
