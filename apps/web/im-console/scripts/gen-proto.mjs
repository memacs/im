import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const consoleDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const root = join(consoleDir, "../../..");
const protoDir = join(root, "proto");
const outJs = join(consoleDir, "src/protocol/generated.js");
const outDts = join(consoleDir, "src/protocol/generated.d.ts");

mkdirSync(dirname(outJs), { recursive: true });

const protos = [
  "common.proto",
  "auth.proto",
  "message.proto",
  "sync.proto",
  "passthrough.proto",
  "group.proto",
  "room.proto",
  "friend.proto",
  "channel.proto",
].map((f) => join(protoDir, f));

const pbjs = spawnSync(
  "npx",
  [
    "pbjs",
    "-t",
    "static-module",
    "-w",
    "es6",
    "-p",
    protoDir,
    "-o",
    outJs,
    ...protos,
  ],
  { cwd: consoleDir, stdio: "inherit", shell: true },
);

if (pbjs.status !== 0) process.exit(pbjs.status ?? 1);

const pbts = spawnSync("npx", ["pbts", "-o", outDts, outJs], {
  cwd: consoleDir,
  stdio: "inherit",
  shell: true,
});

if (pbts.status !== 0) process.exit(pbts.status ?? 1);

console.log("proto →", outJs);
