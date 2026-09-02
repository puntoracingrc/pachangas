import { access, mkdir } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const root = process.cwd();
const beforeRoot = path.resolve(process.env.V3H_BEFORE_CAPTURES ?? "/tmp/v3h-visual-audit/v3h-before-production");
const afterRoot = path.resolve(process.env.V3H_AFTER_CAPTURES ?? "/tmp/v3h-visual-audit/v3h-final-captures");
const journeyRoot = path.resolve(process.env.V3H_JOURNEY_CAPTURES ?? "/tmp/v3h-visual-audit/v3h-journeys");
const outputRoot = path.join(root, "docs", "official-ui-v3h");

const palette = {
  background: "#07130f",
  panel: "#10221b",
  rule: "#315248",
  text: "#f3f7f5",
  muted: "#afc2ba",
  accent: "#c8ef5d",
  cyan: "#51cfdf",
};

function escapeXml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function labelSvg(width, height, title, subtitle = "") {
  return Buffer.from(`
    <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" xmlns="http://www.w3.org/2000/svg">
      <rect width="${width}" height="${height}" fill="${palette.panel}"/>
      <rect x="0" y="${height - 2}" width="${width}" height="2" fill="${palette.rule}"/>
      <text x="18" y="28" fill="${palette.text}" font-family="Arial, sans-serif" font-size="18" font-weight="700">${escapeXml(title)}</text>
      ${subtitle ? `<text x="18" y="50" fill="${palette.muted}" font-family="Arial, sans-serif" font-size="13">${escapeXml(subtitle)}</text>` : ""}
    </svg>
  `);
}

async function tile({ source, title, subtitle }, width, height) {
  await access(source);
  const labelHeight = 64;
  const image = await sharp(source)
    .resize(width - 24, height - labelHeight - 24, { fit: "contain", background: palette.background })
    .extend({ top: 12, bottom: 12, left: 12, right: 12, background: palette.background })
    .png()
    .toBuffer();

  return sharp({ create: { width, height, channels: 4, background: palette.panel } })
    .composite([
      { input: labelSvg(width, labelHeight, title, subtitle), left: 0, top: 0 },
      { input: image, left: 0, top: labelHeight },
    ])
    .png()
    .toBuffer();
}

async function createSheet(filename, title, subtitle, rows, { columns = 3, cellWidth = 520 } = {}) {
  const gap = 12;
  const margin = 24;
  const headerHeight = 94;
  const rowHeights = rows.map((row) => row.height ?? 390);
  const width = margin * 2 + columns * cellWidth + (columns - 1) * gap;
  const height = headerHeight + margin * 2 + rowHeights.reduce((sum, value) => sum + value, 0) + gap * Math.max(0, rows.length - 1);
  const composites = [{ input: labelSvg(width - margin * 2, headerHeight - 12, title, subtitle), left: margin, top: 12 }];

  let top = headerHeight + margin;
  for (let rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
    const row = rows[rowIndex];
    for (let columnIndex = 0; columnIndex < row.cells.length; columnIndex += 1) {
      composites.push({
        input: await tile(row.cells[columnIndex], cellWidth, rowHeights[rowIndex]),
        left: margin + columnIndex * (cellWidth + gap),
        top,
      });
    }
    top += rowHeights[rowIndex] + gap;
  }

  await sharp({ create: { width, height, channels: 4, background: palette.background } })
    .composite(composites)
    .png({ compressionLevel: 9, palette: true })
    .toFile(path.join(outputRoot, filename));
}

const after = (surface, viewport) => path.join(afterRoot, `${surface}--${viewport}.jpg`);
const before = (surface, viewport) => path.join(beforeRoot, `${surface}--${viewport}.jpg`);
const cell = (source, title, subtitle = "SIMULACION · datos ficticios · sin escritura remota") => ({ source, title, subtitle });

await mkdir(outputRoot, { recursive: true });

await createSheet(
  "V3H_SOCIAL_CORE_DESKTOP_CONTACT_SHEET.png",
  "Official UI V3H · Social Core · Desktop",
  "1440x900 · producto social, Demo local y estados publicos",
  [
    { cells: [cell(after("home-visitor", "desktop"), "Landing", "PUBLICO · sin sesion · sin escritura"), cell(after("demo-review", "desktop"), "Revision rapida"), cell(after("demo-inicio-player", "desktop"), "Inicio jugador")] },
    { cells: [cell(after("demo-partido", "desktop"), "Partidos"), cell(after("demo-retos", "desktop"), "Retos"), cell(after("demo-mercado", "desktop"), "Mercado")] },
    { cells: [cell(after("demo-equipo", "desktop"), "Equipo"), cell(after("demo-perfil", "desktop"), "Perfil"), cell(after("demo-avisos", "desktop"), "Avisos")] },
  ],
);

await createSheet(
  "V3H_SOCIAL_CORE_PORTRAIT_CONTACT_SHEET.png",
  "Official UI V3H · Social Core · Portrait",
  "390x844 · lectura directa, acciones tactiles y jerarquia estable",
  [
    { height: 610, cells: [cell(after("home-visitor", "portrait"), "Landing", "PUBLICO · sin sesion · sin escritura"), cell(after("demo-review", "portrait"), "Revision rapida"), cell(after("demo-inicio-free-agent", "portrait"), "Usuario nuevo")] },
    { height: 610, cells: [cell(after("demo-partido", "portrait"), "Partidos"), cell(after("demo-retos", "portrait"), "Retos"), cell(after("demo-mercado", "portrait"), "Mercado")] },
    { height: 610, cells: [cell(after("demo-equipo", "portrait"), "Equipo"), cell(after("demo-perfil", "portrait"), "Perfil"), cell(after("demo-avisos", "portrait"), "Avisos")] },
  ],
);

await createSheet(
  "V3H_SOCIAL_CORE_LANDSCAPE_CONTACT_SHEET.png",
  "Official UI V3H · Mobile Game Landscape",
  "844x390 · sin overflow horizontal · controles de 40 px minimo",
  [
    { height: 330, cells: [cell(after("demo-inicio-admin", "landscape"), "Inicio admin"), cell(after("demo-partido", "landscape"), "Proximo partido"), cell(after("demo-partido-alineacion", "landscape"), "Alineacion")] },
    { height: 330, cells: [cell(after("demo-partido-resultado", "landscape"), "Resultado"), cell(after("demo-partido-admin", "landscape"), "Administrar"), cell(after("demo-retos", "landscape"), "Retos")] },
    { height: 330, cells: [cell(after("demo-mercado", "landscape"), "Mercado"), cell(after("demo-equipo", "landscape"), "Equipo"), cell(after("demo-avisos", "landscape"), "Avisos")] },
  ],
);

await createSheet(
  "V3H_EMPTY_STATES_CONTACT_SHEET.png",
  "Official UI V3H · Empty States",
  "Sin usuarios reales · una explicacion y una salida clara",
  [
    { height: 500, cells: [cell(after("retos", "desktop"), "Retos sin sesion", "ESTADO REAL · sin datos inventados"), cell(after("equipo", "desktop"), "Equipo sin sesion", "ESTADO REAL · sin datos inventados"), cell(after("avisos", "desktop"), "Avisos sin sesion", "ESTADO REAL · sin datos inventados")] },
    { height: 560, cells: [cell(after("retos", "portrait"), "Retos · portrait", "ESTADO REAL · sin datos inventados"), cell(after("equipo", "portrait"), "Equipo · portrait", "ESTADO REAL · sin datos inventados"), cell(after("demo-inicio-free-agent", "portrait"), "Jugador sin equipo")] },
  ],
);

const journeyFiles = [
  ["01-usuario-nuevo.png", "1 · Usuario nuevo"],
  ["02-jugador-con-equipo.png", "2 · Jugador con equipo"],
  ["03-owner-del-equipo.png", "3 · Owner del equipo"],
  ["04-crear-partido.png", "4 · Crear partido"],
  ["05-retar-rival.png", "5 · Retar rival"],
  ["06-buscar-jugador.png", "6 · Buscar jugador"],
  ["07-resolver-avisos.png", "7 · Resolver Avisos"],
];
await createSheet(
  "V3H_END_TO_END_JOURNEYS_CONTACT_SHEET.png",
  "Official UI V3H · End-to-end Journeys",
  "Siete recorridos · LOCAL SESSION ONLY · contadores remotos a cero",
  [
    { cells: journeyFiles.slice(0, 3).map(([file, title]) => cell(path.join(journeyRoot, file), title)) },
    { cells: journeyFiles.slice(3, 6).map(([file, title]) => cell(path.join(journeyRoot, file), title)) },
    { cells: [cell(path.join(journeyRoot, journeyFiles[6][0]), journeyFiles[6][1])] },
  ],
);

await createSheet(
  "V3H_BEFORE_AFTER_CONTACT_SHEET.png",
  "Official UI V3H · Before / After",
  "Produccion previa frente al Release Candidate local, con el mismo viewport",
  [
    { cells: [cell(before("home-visitor", "desktop"), "ANTES · Landing", "PRODUCCION PREVIA"), cell(after("home-visitor", "desktop"), "DESPUES · Landing", "PUBLICO · sin sesion · sin escritura")], height: 420 },
    { cells: [cell(before("retos", "desktop"), "ANTES · Retos", "PRODUCCION PREVIA"), cell(after("retos", "desktop"), "DESPUES · Retos")], height: 420 },
    { cells: [cell(before("mercado", "desktop"), "ANTES · Mercado", "PRODUCCION PREVIA"), cell(after("mercado", "desktop"), "DESPUES · Mercado")], height: 420 },
    { cells: [cell(before("demo-inicio-admin", "landscape"), "ANTES · Demo landscape", "PRODUCCION PREVIA"), cell(after("demo-inicio-admin", "landscape"), "DESPUES · Demo landscape")], height: 330 },
  ],
  { columns: 2, cellWidth: 720 },
);

console.log(JSON.stringify({ outputRoot, files: 6 }, null, 2));
