import { existsSync } from "node:fs";
import { cp, mkdir } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const root = process.cwd();
const outputRoot = path.join(root, "docs", "official-ui-v2-1");
const capturesRoot = path.join(outputRoot, "captures");
const regressionArchiveRoot = path.join(capturesRoot, "product-regression");
const parityRoot = path.join(root, "artifacts", "visual-audit-v1", "official-ui-v2-1-deep-parity");
const regressionRoot = path.join(root, "artifacts", "visual-audit-v1", "official-ui-v2-1-product-regression");
const fixRegressionRoot = path.join(root, "artifacts", "visual-audit-v1", "official-ui-v2-1-regression");
const finalFixRegressionRoot = path.join(root, "artifacts", "visual-audit-v1", "official-ui-v2-1-regression-2");
const performanceRoot = path.join(root, "artifacts", "visual-audit-v1", "official-ui-v2-1-performance");
const authenticatedRoot = path.join(root, "artifacts", "visual-audit-v1", "official-ui-v2-1-final-preview-manual");
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
  const name = `${surface}--${viewport}.jpg`;
  const current = path.join(parityRoot, name);
  return existsSync(current) ? current : path.join(capturesRoot, "v2-1", name);
}

function demo(surface, viewport) {
  const name = `${surface}--${viewport}.jpg`;
  const current = path.join(regressionRoot, name);
  return existsSync(current) ? current : path.join(regressionArchiveRoot, name);
}

function officialV2(surface, viewport) {
  const prefix = viewport === "desktop" ? "desktop-1440x900" : viewport === "portrait" ? "portrait-390x844" : "landscape-844x390";
  return path.join(officialV2Root, `${prefix}-${surface}.png`);
}

function authenticated(surface, viewport) {
  const current = path.join(authenticatedRoot, `${surface}--${viewport}.png`);
  return existsSync(current)
    ? current
    : path.join(capturesRoot, "authenticated-final", `${surface}--${viewport}.png`);
}

function authenticatedStaging(name) {
  return path.join(capturesRoot, "authenticated-staging-final", `${name}.png`);
}

function canonicalRole(name) {
  return path.join(capturesRoot, "canonical-role-final", `${name}.png`);
}

function parityRow(label, height, demoSource, currentSource, proposedSource) {
  return {
    label,
    height,
    cells: [
      { source: demoSource, title: "A. DEMO WORLD", subtitle: `${label} · curated baseline` },
      { source: currentSource, title: "B. PRODUCTION V2" },
      { source: proposedSource, title: "C. V2.1 PROPOSAL" },
    ],
  };
}

async function copyEvidence() {
  const curatedEvidence = [
    [parityRoot, "v2-1", [
      "matrix.md", "results.json",
      "v21-home--desktop.jpg", "v21-home--portrait.jpg", "v21-home--landscape.jpg",
      "v21-home--landscape-small.jpg", "v21-home--landscape-wide.jpg",
      "v21-match-next--desktop.jpg", "v21-match-next--portrait.jpg", "v21-match-next--landscape.jpg",
      "v21-match-next--landscape-small.jpg", "v21-match-next--landscape-wide.jpg",
      "v21-match-lineup--landscape.jpg", "v21-match-result--landscape.jpg", "v21-match-admin--landscape.jpg",
      "v21-market--desktop.jpg", "v21-market--portrait.jpg", "v21-market--landscape.jpg",
      "v21-ranking--desktop.jpg", "v21-card--desktop.jpg", "v21-shield--desktop.jpg",
      "v21-notifications--desktop.jpg",
    ]],
    [regressionRoot, "product-regression", [
      "matrix.md", "results.json",
      "demo-inicio-admin--desktop.jpg", "demo-inicio-admin--portrait.jpg", "demo-inicio-admin--landscape.jpg",
      "demo-mercado--desktop.jpg", "demo-mercado--portrait.jpg", "demo-mercado--landscape.jpg",
      "demo-partido--landscape.jpg", "demo-partido-alineacion--landscape.jpg",
      "demo-partido-resultado--landscape.jpg", "demo-partido-admin--landscape.jpg",
      "equipo-identidad--desktop.jpg", "home-visitor--portrait.jpg", "mercado--desktop.jpg",
      "personalizar-carta--desktop.jpg", "ranking--desktop.jpg", "avisos--desktop.jpg",
    ]],
    [fixRegressionRoot, "fix-regression", ["matrix.md", "results.json"]],
    [finalFixRegressionRoot, "fix-regression-final", ["matrix.md", "results.json"]],
    [performanceRoot, "performance", ["matrix.md", "results.json"]],
    [authenticatedRoot, "authenticated-final", [
      "results.json", "rotation-results.json",
      "home-owner--desktop.png", "home-owner--portrait.png", "home-owner--landscape.png",
      "home-player--desktop.png", "home-player--portrait.png", "home-player--landscape.png",
      "home-offline--desktop.png", "home-offline--portrait.png", "home-offline--landscape.png",
      "match-next--desktop.png", "match-lineup--landscape.png", "match-result--landscape.png",
      "market--landscape.png", "ranking--desktop.png", "card--desktop.png", "shield--desktop.png",
    ]],
  ];

  for (const [sourceRoot, destinationName, names] of curatedEvidence) {
    const destination = path.join(capturesRoot, destinationName);
    await mkdir(destination, { recursive: true });
    for (const name of names) {
      const source = path.join(sourceRoot, name);
      if (existsSync(source)) await cp(source, path.join(destination, name));
    }
  }
}

await mkdir(outputRoot, { recursive: true });

const authenticatedOnly = process.env.OFFICIAL_UI_AUTHENTICATED_ONLY === "1";
const parityEssentialsOnly = process.env.OFFICIAL_UI_PARITY_ESSENTIALS_ONLY === "1";

if (!authenticatedOnly) {
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
if (!parityEssentialsOnly) {
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
}

const mobileViewports = parityEssentialsOnly
  ? ["landscape"]
  : ["landscape-small", "landscape", "landscape-wide"];
const mobileLabels = parityEssentialsOnly
  ? ["844x390"]
  : ["667x375", "844x390", "932x430"];
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
      title: `V2.1 PROPOSAL - ${label} - ${mobileLabels[index]}`,
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
  ...(!parityEssentialsOnly ? [
  ["Ranking", null, "ranking", "v21-ranking"],
  ["Avisos", null, "avisos", "v21-notifications"],
  ["Carta", null, "carta", "v21-card"],
  ] : []),
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
        title: `DEMO WORLD - ${label}`,
        subtitle: "Curated baseline; responsive hotfix documented separately",
      },
      { source: officialV2(officialKey, "landscape"), title: `PRODUCTION V2 - ${label}` },
      { source: v21(proposedKey, "landscape"), title: `V2.1 PROPOSAL - ${label}` },
    ],
  })),
);
}

await createSheet(
  "OFFICIAL_UI_V2_1_AUTHENTICATED_FINAL_CONTACT_SHEET.png",
  "Official UI V2.1 - Authenticated staging review",
  "Lecturas canonicas separadas de fixtures visuales; sin PII ni estados inventados",
  [
    {
      label: "Lectura canonica staging - usuario sin equipo",
      height: 460,
      cells: [
        { source: authenticatedStaging("no-team--desktop-1440x900"), title: "CANONICAL STAGING - 1440x900" },
        { source: authenticatedStaging("no-team--portrait-390x844"), title: "CANONICAL STAGING - 390x844" },
        { source: authenticatedStaging("no-team--landscape-844x390"), title: "CANONICAL STAGING - 844x390" },
      ],
    },
    {
      label: "Estados canonicos staging",
      height: 460,
      cells: [
        { source: authenticatedStaging("no-team-identity--desktop-1440x900"), title: "CANONICAL STAGING - equipo vacio" },
        { source: authenticatedStaging("no-team-card--desktop-1440x900"), title: "CANONICAL STAGING - carta pendiente" },
        { source: authenticatedStaging("no-team-ranking--desktop-1440x900"), title: "CANONICAL STAGING - ranking" },
      ],
    },
    {
      label: "Avisos y portrait canonicos",
      height: 460,
      cells: [
        { source: authenticatedStaging("no-team-notifications--desktop-1440x900"), title: "CANONICAL STAGING - preferencias" },
        { source: authenticatedStaging("no-team-notifications-empty--desktop-1440x900"), title: "CANONICAL STAGING - avisos vacios" },
        { source: authenticatedStaging("no-team-card--portrait-390x844"), title: "CANONICAL STAGING - carta portrait" },
      ],
    },
    {
      label: "Owner real sin ficha - escudo protagonista",
      height: 460,
      cells: [
        { source: canonicalRole("owner-no-profile-home--desktop-1440x900"), title: "CANONICAL STAGING - owner 1440x900" },
        { source: canonicalRole("owner-no-profile-home--portrait-390x844"), title: "CANONICAL STAGING - owner 390x844" },
        { source: canonicalRole("owner-no-profile-home--landscape-844x390"), title: "CANONICAL STAGING - owner 844x390" },
      ],
    },
    {
      label: "Escudo canonico base",
      height: 460,
      cells: [
        { source: canonicalRole("owner-base-shield--desktop-1440x900"), title: "CANONICAL STAGING - base 1440x900" },
        { source: canonicalRole("owner-base-shield--portrait-390x844"), title: "CANONICAL STAGING - base 390x844" },
        { source: canonicalRole("owner-base-shield--landscape-844x390"), title: "CANONICAL STAGING - base 844x390" },
      ],
    },
    {
      label: "Escudo canonico configurado - revision 1",
      height: 460,
      cells: [
        { source: canonicalRole("owner-configured-shield--desktop-1440x900"), title: "CANONICAL STAGING - configurado 1440x900" },
        { source: canonicalRole("owner-configured-shield--portrait-390x844"), title: "CANONICAL STAGING - configurado 390x844" },
        { source: canonicalRole("owner-configured-shield--landscape-844x390"), title: "CANONICAL STAGING - configurado 844x390" },
      ],
    },
    {
      label: "Jugador real - permisos canonicos de jugador",
      height: 460,
      cells: [
        { source: canonicalRole("player-canonical-home--desktop-1440x900"), title: "CANONICAL STAGING - jugador 1440x900" },
        { source: canonicalRole("player-canonical-home--portrait-390x844"), title: "CANONICAL STAGING - jugador 390x844" },
        { source: canonicalRole("player-canonical-home--landscape-844x390"), title: "CANONICAL STAGING - jugador 844x390" },
      ],
    },
    {
      label: "Cobertura visual de roles - no es lectura canonica",
      height: 460,
      cells: [
        { source: authenticated("home-owner", "desktop"), title: "FIXTURE VISUAL - owner" },
        { source: authenticated("home-player", "desktop"), title: "FIXTURE VISUAL - jugador" },
        { source: authenticated("home-offline", "desktop"), title: "FIXTURE VISUAL - offline" },
      ],
    },
  ],
  { columns: 3, cellWidth: 580 },
);

await copyEvidence();
console.log(`Official UI V2.1 evidence written to ${outputRoot}`);
