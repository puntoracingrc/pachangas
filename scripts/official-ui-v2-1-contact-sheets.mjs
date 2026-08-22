import { cp, mkdir, readdir, rm } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const root = process.cwd();
const outputRoot = path.join(root, "docs", "official-ui-v2-1");
const capturesRoot = path.join(outputRoot, "captures");
const parityRoot = path.join(root, "artifacts", "visual-audit-v1", "official-ui-v2-1-deep-parity");
const regressionRoot = path.join(root, "artifacts", "visual-audit-v1", "official-ui-v2-1-product-regression");
const fixRegressionRoot = path.join(root, "artifacts", "visual-audit-v1", "official-ui-v2-1-regression");
const finalFixRegressionRoot = path.join(root, "artifacts", "visual-audit-v1", "official-ui-v2-1-regression-2");
const performanceRoot = path.join(root, "artifacts", "visual-audit-v1", "official-ui-v2-1-performance");
const officialV2Root = path.join(root, "docs", "official-ui-v2", "captures", "after");

const palette = {
  background: "#071019",
  panel: "#101c27",
  rule: "#254358",
  text: "#f4f7f9",
  muted: "#a9bac6",
  accent: "#5ad89b",
};

function escapeXml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function svgLabel(width, height, title, subtitle = "") {
  return Buffer.from(`
    <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" xmlns="http://www.w3.org/2000/svg">
      <rect width="${width}" height="${height}" fill="${palette.panel}"/>
      <rect x="0" y="${height - 2}" width="${width}" height="2" fill="${palette.rule}"/>
      <text x="18" y="27" fill="${palette.text}" font-family="Arial, sans-serif" font-size="18" font-weight="700">${escapeXml(title)}</text>
      ${subtitle ? `<text x="18" y="49" fill="${palette.muted}" font-family="Arial, sans-serif" font-size="13">${escapeXml(subtitle)}</text>` : ""}
    </svg>
  `);
}

async function imageTile(source, width, height, title, subtitle) {
  const labelHeight = 62;
  const imageHeight = height - labelHeight;
  const image = await sharp(source)
    .resize(width - 24, imageHeight - 24, { fit: "contain", background: palette.background })
    .extend({
      top: 12,
      bottom: 12,
      left: 12,
      right: 12,
      background: palette.background,
    })
    .png()
    .toBuffer();

  return sharp({ create: { width, height, channels: 4, background: palette.panel } })
    .composite([
      { input: svgLabel(width, labelHeight, title, subtitle), top: 0, left: 0 },
      { input: image, top: labelHeight, left: 0 },
    ])
    .png()
    .toBuffer();
}

async function createSheet(filename, title, subtitle, rows, options = {}) {
  const columns = options.columns ?? Math.max(...rows.map((row) => row.cells.length));
  const cellWidth = options.cellWidth ?? 600;
  const gap = 12;
  const margin = 24;
  const headerHeight = 96;
  const width = margin * 2 + columns * cellWidth + (columns - 1) * gap;
  const rowHeights = rows.map((row) => row.height ?? 420);
  const height = headerHeight + margin + rowHeights.reduce((total, rowHeight) => total + rowHeight, 0)
    + Math.max(0, rows.length - 1) * gap + margin;
  const composites = [{
    input: svgLabel(width - margin * 2, headerHeight - 12, title, subtitle),
    left: margin,
    top: 12,
  }];

  let top = headerHeight + margin;
  for (let rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
    const row = rows[rowIndex];
    const rowHeight = rowHeights[rowIndex];
    for (let column = 0; column < row.cells.length; column += 1) {
      const cell = row.cells[column];
      const tile = await imageTile(cell.source, cellWidth, rowHeight, cell.title, cell.subtitle ?? row.label);
      composites.push({ input: tile, left: margin + column * (cellWidth + gap), top });
    }
    top += rowHeight + gap;
  }

  await sharp({ create: { width, height, channels: 4, background: palette.background } })
    .composite(composites)
    .png({ compressionLevel: 9, palette: true })
    .toFile(path.join(outputRoot, filename));
}

function v21(surface, viewport) {
  return path.join(parityRoot, `${surface}--${viewport}.jpg`);
}

function demo(surface, viewport) {
  return path.join(regressionRoot, `${surface}--${viewport}.jpg`);
}

function officialV2(surface, viewport) {
  const prefix = viewport === "desktop" ? "desktop-1440x900" : viewport === "portrait" ? "portrait-390x844" : "landscape-844x390";
  return path.join(officialV2Root, `${prefix}-${surface}.png`);
}

function parityRow(label, height, demoSource, currentSource, proposedSource) {
  return {
    label,
    height,
    cells: [
      { source: demoSource, title: "A. Demo World" },
      { source: currentSource, title: "B. Official UI V2" },
      { source: proposedSource, title: "C. Official UI V2.1" },
    ],
  };
}

async function copyEvidence() {
  await rm(capturesRoot, { recursive: true, force: true });
  await mkdir(path.join(capturesRoot, "v2-1"), { recursive: true });
  await mkdir(path.join(capturesRoot, "product-regression"), { recursive: true });
  await mkdir(path.join(capturesRoot, "fix-regression"), { recursive: true });
  await mkdir(path.join(capturesRoot, "fix-regression-final"), { recursive: true });
  await mkdir(path.join(capturesRoot, "performance"), { recursive: true });
  for (const [sourceRoot, destination] of [
    [parityRoot, path.join(capturesRoot, "v2-1")],
    [regressionRoot, path.join(capturesRoot, "product-regression")],
    [fixRegressionRoot, path.join(capturesRoot, "fix-regression")],
    [finalFixRegressionRoot, path.join(capturesRoot, "fix-regression-final")],
    [performanceRoot, path.join(capturesRoot, "performance")],
  ]) {
    for (const name of await readdir(sourceRoot)) {
      if (!name.endsWith(".jpg") && name !== "results.json" && name !== "matrix.md") continue;
      if (name === "premium-art-pack-contact-sheet.jpg") continue;
      await cp(path.join(sourceRoot, name), path.join(destination, name));
    }
  }
}

await mkdir(outputRoot, { recursive: true });

await createSheet(
  "OFFICIAL_UI_V2_1_HOME_PARITY_CONTACT_SHEET.png",
  "Official UI V2.1 - Home parity",
  "Demo World vs Official UI V2 vs propuesta V2.1",
  [
    parityRow("Desktop 1440x900", 470, demo("demo-inicio-admin", "desktop"), officialV2("inicio", "desktop"), v21("v21-home", "desktop")),
    parityRow("Portrait 390x844", 720, demo("demo-inicio-admin", "portrait"), officialV2("inicio", "portrait"), v21("v21-home", "portrait")),
    parityRow("Landscape 844x390", 350, demo("demo-inicio-admin", "landscape"), officialV2("inicio", "landscape"), v21("v21-home", "landscape")),
  ],
);

const matchSurfaces = [
  { label: "Proximo", demo: "demo-partido", official: "partido-proximo", proposed: "v21-match-next" },
  { label: "Alineacion", demo: "demo-partido-alineacion", official: "alineacion", proposed: "v21-match-lineup" },
  { label: "Resultado", demo: "demo-partido-resultado", official: "resultado", proposed: "v21-match-result" },
  { label: "Admin", demo: "demo-partido-admin", official: "admin-partido", proposed: "v21-match-admin" },
];
const matchRows = [];
for (const surface of matchSurfaces) {
  matchRows.push(
    parityRow(`${surface.label} - desktop 1440x900`, 470, demo(surface.demo, "desktop"), officialV2(surface.official, "desktop"), v21(surface.proposed, "desktop")),
    parityRow(`${surface.label} - portrait 390x844`, 720, demo(surface.demo, "portrait"), officialV2(surface.official, "portrait"), v21(surface.proposed, "portrait")),
    parityRow(`${surface.label} - landscape 844x390`, 350, demo(surface.demo, "landscape"), officialV2(surface.official, "landscape"), v21(surface.proposed, "landscape")),
  );
}
await createSheet(
  "OFFICIAL_UI_V2_1_MATCH_PARITY_CONTACT_SHEET.png",
  "Official UI V2.1 - Match Hub parity",
  "Proximo, Alineacion, Resultado y Admin en desktop, portrait y landscape",
  matchRows,
);

await createSheet(
  "OFFICIAL_UI_V2_1_MARKET_PARITY_CONTACT_SHEET.png",
  "Official UI V2.1 - Market parity",
  "Filtros compactos, lista escaneable y detalle contextual",
  [
    parityRow("Desktop 1440x900", 470, demo("demo-mercado", "desktop"), officialV2("mercado", "desktop"), v21("v21-market", "desktop")),
    parityRow("Portrait 390x844", 720, demo("demo-mercado", "portrait"), officialV2("mercado", "portrait"), v21("v21-market", "portrait")),
    parityRow("Landscape 844x390", 350, demo("demo-mercado", "landscape"), officialV2("mercado", "landscape"), v21("v21-market", "landscape")),
  ],
);

const mobileViewports = ["landscape-small", "landscape", "landscape-wide"];
const mobileLabels = ["667x375", "844x390", "932x430"];
const mobileSurfaces = [
  ["Inicio", "v21-home"],
  ["Proximo", "v21-match-next"],
  ["Alineacion", "v21-match-lineup"],
  ["Resultado", "v21-match-result"],
  ["Admin", "v21-match-admin"],
  ["Mercado", "v21-market"],
];
await createSheet(
  "OFFICIAL_UI_V2_1_MOBILE_GAME_CONTACT_SHEET.png",
  "Official UI V2.1 - Mobile Game Landscape",
  "Interior productivo adaptado al shell horizontal existente",
  mobileSurfaces.map(([label, surface]) => ({
    label,
    height: 350,
    cells: mobileViewports.map((viewport, index) => ({
      source: v21(surface, viewport),
      title: `${label} - ${mobileLabels[index]}`,
    })),
  })),
);

const comparisonSurfaces = [
  ["Inicio", "demo-inicio-admin", "inicio", "v21-home"],
  ["Proximo", "demo-partido", "partido-proximo", "v21-match-next"],
  ["Alineacion", "demo-partido-alineacion", "alineacion", "v21-match-lineup"],
  ["Resultado", "demo-partido-resultado", "resultado", "v21-match-result"],
  ["Admin", "demo-partido-admin", "admin-partido", "v21-match-admin"],
  ["Mercado", "demo-mercado", "mercado", "v21-market"],
  ["Ranking", null, "ranking", "v21-ranking"],
  ["Avisos", null, "avisos", "v21-notifications"],
  ["Carta", null, "carta", "v21-card"],
];
const legacyDemoRoot = path.join(root, "docs", "official-ui-v2", "captures", "demo");
await createSheet(
  "OFFICIAL_UI_V2_1_DEMO_OFFICIAL_COMPARISON.png",
  "Official UI V2.1 - Demo / Official comparison",
  "Comparacion estructural en Mobile Game Landscape 844x390",
  comparisonSurfaces.map(([label, demoKey, officialKey, proposedKey]) => ({
    label,
    height: 350,
    cells: [
      {
        source: demoKey
          ? demo(demoKey, "landscape")
          : path.join(legacyDemoRoot, `landscape-844x390-${officialKey}.png`),
        title: `Demo - ${label}`,
      },
      { source: officialV2(officialKey, "landscape"), title: `Official V2 - ${label}` },
      { source: v21(proposedKey, "landscape"), title: `V2.1 - ${label}` },
    ],
  })),
);

await copyEvidence();
console.log(`Official UI V2.1 evidence written to ${outputRoot}`);
