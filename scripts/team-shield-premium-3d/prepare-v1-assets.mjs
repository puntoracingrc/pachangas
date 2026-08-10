import { copyFile, mkdir, readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";

const root = process.cwd();
const sourceDirectory = path.join(root, "public/team-shield-premium-3d");
const targetDirectory = path.join(root, "public/team-shield-premium-v1");
const assets = [
  ["ball-premium-frame-0.webp", "ball-frame-0.c3565074.webp", "c3565074"],
  ["ball-premium-frame-1.webp", "ball-frame-1.a056b70d.webp", "a056b70d"],
  ["ball-premium-frame-2.webp", "ball-frame-2.1e63053b.webp", "1e63053b"],
  ["ball-premium-frame-3.webp", "ball-frame-3.c29b00c7.webp", "c29b00c7"],
  ["ball-premium-frame-4.webp", "ball-frame-4.2571172b.webp", "2571172b"],
  ["ball-premium-frame-5.webp", "ball-frame-5.7a0354ad.webp", "7a0354ad"],
  ["ball-premium-frame-6.webp", "ball-frame-6.dbf823ca.webp", "dbf823ca"],
  ["ball-premium-frame-7.webp", "ball-frame-7.21039a34.webp", "21039a34"],
  ["shield-premium-copper.webp", "border-copper.9b756acb.webp", "9b756acb"],
  ["shield-premium-silver.webp", "border-silver.dde0edf8.webp", "dde0edf8"],
  ["shield-premium-gold.webp", "border-gold.96413f0c.webp", "96413f0c"],
];

await mkdir(targetDirectory, { recursive: true });
for (const [sourceName, targetName, expectedHash] of assets) {
  const source = path.join(sourceDirectory, sourceName);
  const digest = createHash("sha256").update(await readFile(source)).digest("hex").slice(0, 8);
  if (digest !== expectedHash) {
    throw new Error(`${sourceName} changed (${digest}); regenerate the content-hashed manifest intentionally.`);
  }
  await copyFile(source, path.join(targetDirectory, targetName));
}

console.log(`Prepared ${assets.length} immutable Team Shield Premium V1 assets.`);
