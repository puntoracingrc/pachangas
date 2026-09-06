import { catalogEntry } from "./player-cosmetics-catalog";
import type { RewardRarity } from "./reward-rarity-effects";
// Collective V3 catalogue: 20260808205638_achievement_catalog_v3.sql.
// Repeat occurrences retain base rarity; first occurrences gain one tier (capped at legendary).
export const rewards: { rarity: RewardRarity; title: string; description: string; context: string }[] = [
  { rarity: "common", title: "Doblete", description: "El equipo marca exactamente 2 goles en un partido confirmado.", context: "Logro de equipo · Repetido" },
  { rarity: "uncommon", title: "Hat-trick", description: "El equipo marca exactamente 3 goles en un partido confirmado.", context: "Logro de equipo · Repetido" },
  { rarity: "rare", title: "Manita", description: "El equipo marca exactamente 5 goles en un partido confirmado.", context: "Logro de equipo · Repetido" },
  { rarity: "epic", title: "Primer dominio absoluto", description: "Gana un Reto por cuatro o más goles de diferencia sin encajar.", context: "Logro de equipo · Primera vez" },
  { rarity: "legendary", title: "Quinientos partidos", description: "Completa 500 partidos canónicos entre Pachangas y Retos.", context: "Trayectoria del equipo" },
];

// Possible results from collective reward pools, remapped by player_cosmetics_v1.
// These fixtures illustrate the reveal; they are not fixed achievement rewards.
export const prizes = [
  { points: 6, key: null, color: "#b7f452" },
  { points: 0, key: "player.frame.barrio.copper", color: "#b96737" },
  { points: 10, key: "player.title.team_engine", color: "#5aa7ff" },
  { points: 0, key: "player.frame.future.navy", color: "#173a67" },
  { points: 0, key: "player.frame.retro.chrome", color: "#d8dde0" },
];
export function prizeTitle(index: number) {
  const prize = prizes[index];
  return catalogEntry(prize.key)?.name ?? `+${prize.points} puntos`;
}
export function PrizePreview({ index, prizeOverride }: { index: number; prizeOverride?: { points: number; key: string | null; color: string } }) {
  const prize = prizeOverride ?? prizes[index];
  const entry = catalogEntry(prize.key);
  const frame = entry?.slot === "frame";
  return <svg viewBox="0 0 300 250" role="img" aria-label={frame ? `Vista previa del marco ${entry.name}` : entry?.name ?? "Puntos"}>
    <defs><linearGradient id={`metal-${index}`} x2="1" y2="1"><stop stopColor={prize.color}/><stop offset=".45" stopColor="#f0f5f6"/><stop offset=".55" stopColor={prize.color}/><stop offset="1" stopColor={prize.color}/></linearGradient></defs>
    {frame ? <>
      <path d="M75 15H225V195L150 235 75 195Z" fill="#101c29" stroke={`url(#metal-${index})`} strokeWidth="14"/>
      <path d="M89 30H211V187L150 220 89 187Z" fill="none" stroke={prize.color} strokeWidth="3"/>
      <circle cx="150" cy="92" r="29" fill="#83939f"/><path d="M108 167v-17a42 34 0 0 1 84 0v17" fill="#83939f"/>
    </> : entry ? <>
      <circle cx="150" cy="125" r="94" fill="#132a35" stroke={prize.color} strokeWidth="6"/>
      <path d="m150 78 14 30 33 4-24 24 6 33-29-16-29 16 6-33-24-24 33-4Z" fill={prize.color}/>
    </> : <>
      <defs>
        <linearGradient id={`coin-${index}`} x1="0" y1="0" x2="1" y2="1">
          <stop stopColor="#eff8ce"/><stop offset=".35" stopColor="#b3ca79"/><stop offset="1" stopColor="#526a38"/>
        </linearGradient>
      </defs>
      <ellipse cx="150" cy="218" rx="65" ry="9" fill="#000" opacity=".2"/>
      <circle cx="150" cy="130" r="80" fill="#3e512e"/>
      <circle cx="150" cy="121" r="80" fill={`url(#coin-${index})`}/>
      <circle cx="150" cy="121" r="66" fill="#20372c" stroke="#d5e6ac" strokeWidth="2"/>
      <circle cx="150" cy="121" r="59" fill="none" stroke="#b3ca79" strokeOpacity=".3"/>
      <path d="m150 81 12 26 29 4-21 21 5 29-25-14-25 14 5-29-21-21 29-4Z" fill={`url(#coin-${index})`}/>
      <path d="M91 78a73 73 0 0 1 92-23" fill="none" stroke="#f4ffdb" strokeWidth="3" strokeLinecap="round" opacity=".7"/>
    </>}
  </svg>;
}

