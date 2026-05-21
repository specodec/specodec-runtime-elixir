import { execSync } from "child_process";
import { readFileSync, existsSync, mkdirSync, rmSync, readdirSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dir = dirname(fileURLToPath(import.meta.url));
const VEC_DIR = join(__dir, "vectors");
const GENERATED = join(__dir, "src", "generated");
const OUT_DIR = join(__dir, "output");
const RUNTIME = join(__dir, "..", "..");

function run(cmd) {
  console.log("  >", cmd);
  execSync(cmd, { stdio: "inherit" });
}

function ensure(dir) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

console.log("\n=== Step 1: Install dependencies ===");
run(`cd ${__dir} && npm install`);

console.log("\n=== Step 2: Generate emit code ===");
if (existsSync(GENERATED)) rmSync(GENERATED, { recursive: true });
ensure(GENERATED);
run(`cd ${__dir} && node_modules/.bin/tsp compile ${__dir}/alltypes.tsp --emit=@specodec/typespec-emitter-elixir --option @specodec/typespec-emitter-elixir.emitter-output-dir=${GENERATED}`);

console.log("\n=== Step 3: Compile runtime ===");
run(`cd ${RUNTIME} && MIX_ENV=test mix clean 2>/dev/null; MIX_ENV=test mix deps.get 2>/dev/null; MIX_ENV=test mix compile 2>/dev/null`);

console.log("\n=== Step 4: Run tests ===");
if (existsSync(OUT_DIR)) rmSync(OUT_DIR, { recursive: true });
ensure(OUT_DIR);
try { run(`cd ${RUNTIME} && VEC_DIR=${VEC_DIR} OUT_DIR=${OUT_DIR} elixir tests/interop/run.exs`); } catch (e) { console.log("Elixir tests completed (some failures expected)"); }

console.log("\n=== Step 5: Compare output ===");
const manifest = JSON.parse(readFileSync(join(VEC_DIR, "manifest.json"), "utf-8"));
let match = 0, mismatch = 0;

for (const [name] of Object.entries(manifest.scalars || {})) {
  const expected = join(VEC_DIR, "scalars", `${name}.mp`);
  const actual = join(OUT_DIR, "scalars", `${name}.mp`);
  if (!existsSync(actual)) { mismatch++; console.log(`MISSING: ${name}.mp`); continue; }
  if (readFileSync(expected).equals(readFileSync(actual))) match++;
  else { mismatch++; console.log(`MISMATCH: ${name}.mp`); }
}
for (const model of [...(manifest.testModels || []), ...(manifest.testUnions || [])]) {
  for (const [outExt, vecExt] of [["msgpack","msgpack"], ["json","json"], ["unformatted.json","json"], ["gron","gron"]]) {
    const expected = join(VEC_DIR, `${model}.${vecExt}`);
    const actual = join(OUT_DIR, `${model}.${outExt}`);
    if (!existsSync(expected)) continue;
    if (!existsSync(actual)) { mismatch++; console.log(`MISSING: ${model}.${outExt}`); continue; }
    if (readFileSync(expected).equals(readFileSync(actual))) match++;
    else { mismatch++; console.log(`MISMATCH: ${model}.${outExt}`); }
  }
}
const total = match + mismatch;
console.log(`${match}/${total} match, ${mismatch} mismatch`);
if (mismatch > 0) process.exit(1);
console.log("\n=== ALL PASSED ===");
