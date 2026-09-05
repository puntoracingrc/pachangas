"use client";

import { useState } from "react";
import dynamic from "next/dynamic";
import { catalogEntry, PLAYER_COSMETIC_SLOT_LABELS } from "../player-cosmetics-catalog";
import { unlockRewardAudio } from "../reward-box-audio";
import rewardRarityVisuals from "../reward-rarity-visuals.json";
import type { RewardRarity } from "../reward-rarity-effects";

const RewardBoxDemo = dynamic(() => import("../reward-box-demo").then((module) => module.RewardBoxDemo), { ssr: false });
// Collective V3 catalogue: 20260808205638_achievement_catalog_v3.sql.
// Repeat occurrences retain base rarity; first occurrences gain one tier (capped at legendary).
const rewards: { rarity: RewardRarity; title: string; description: string; context: string }[] = [
  { rarity: "common", title: "Doblete", description: "El equipo marca exactamente 2 goles en un partido confirmado.", context: "Logro de equipo · Repetido" },
  { rarity: "uncommon", title: "Hat-trick", description: "El equipo marca exactamente 3 goles en un partido confirmado.", context: "Logro de equipo · Repetido" },
  { rarity: "rare", title: "Manita", description: "El equipo marca exactamente 5 goles en un partido confirmado.", context: "Logro de equipo · Repetido" },
  { rarity: "epic", title: "Primer dominio absoluto", description: "Gana un Reto por cuatro o más goles de diferencia sin encajar.", context: "Logro de equipo · Primera vez" },
  { rarity: "legendary", title: "Quinientos partidos", description: "Completa 500 partidos canónicos entre Pachangas y Retos.", context: "Trayectoria del equipo" },
];

// Possible results from collective reward pools, remapped by player_cosmetics_v1.
// These fixtures illustrate the reveal; they are not fixed achievement rewards.
const prizes = [
  { points: 6, key: null, color: "#b7f452" },
  { points: 0, key: "player.frame.barrio.copper", color: "#b96737" },
  { points: 10, key: "player.title.team_engine", color: "#5aa7ff" },
  { points: 0, key: "player.frame.future.navy", color: "#173a67" },
  { points: 0, key: "player.frame.retro.chrome", color: "#d8dde0" },
];
function prizeTitle(index: number) {
  const prize = prizes[index];
  return catalogEntry(prize.key)?.name ?? `+${prize.points} puntos`;
}
function PrizePreview({ index }: { index: number }) {
  const prize = prizes[index];
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

export default function ChestLab() {
  const [index, setIndex] = useState<number | null>(null);
  const [opened, setOpened] = useState<number[]>([]);
  const [completed, setCompleted] = useState(false);
  const current = index === null ? null : rewards[index];
  const prize = index === null ? null : prizes[index];
  const cosmetic = catalogEntry(prize?.key);
  const pending = rewards.map((_, i) => i).filter((i) => !opened.includes(i));
  const remaining = pending.length;
  const start = () => { unlockRewardAudio(); if (completed || pending.length === 0) { setOpened([]); setIndex(0); } else setIndex(pending[0] ?? 0); setCompleted(false); };
  const next = () => {
    if (index === null) return;
    if (pending.length) setIndex(pending[0]);
    else { setIndex(null); setCompleted(true); }
  };
  return <main style={{ minHeight: "100dvh", display: "grid", placeContent: "center", gap: 20, padding: 24, textAlign: "center", background: "#071411", color: "#f4f7f5" }}>
    <h1>{completed ? "¡Todos los cofres abiertos!" : `Tienes ${pending.length} cofres por abrir`}</h1>
    <p>{completed ? "Estos son los premios de esta simulación." : "Premios de ejemplo del catálogo · Simulación sin conceder logros ni premios"}</p>
    {completed ? <ul style={{ listStyle: "none", padding: 0, lineHeight: 2 }}>{rewards.map((reward, i) => <li key={reward.title}><strong>{prizeTitle(i)}{prizes[i].key && prizes[i].points ? ` + ${prizes[i].points} puntos` : ""}</strong><br/><small>Conseguido por: {reward.title}</small></li>)}</ul> : null}
    <button type="button" onClick={start} style={{ padding: "16px 24px", borderRadius: 12, background: "#b7f452", color: "#102009", fontWeight: 800 }}>{completed || pending.length === 0 ? "Repetir la prueba" : "Abrir siguiente cofre"}</button>
    <div style={{ display: "flex", flexWrap: "wrap", gap: 10, justifyContent: "center" }}>
      {rewards.map((reward, i) => !opened.includes(i) ? <button key={reward.rarity} type="button" onClick={() => { unlockRewardAudio(); setCompleted(false); setIndex(i); }} style={{ padding: "12px 18px", borderRadius: 8, border: `1px solid ${rewardRarityVisuals[reward.rarity].accent}`, background: rewardRarityVisuals[reward.rarity].dark, color: rewardRarityVisuals[reward.rarity].accent }}>{rewardRarityVisuals[reward.rarity].label}</button> : null)}
    </div>
    {current ? <RewardBoxDemo
      key={index}
      rarity={current.rarity}
      open
      onClose={() => setIndex(null)}
      eyebrow={cosmetic ? PLAYER_COSMETIC_SLOT_LABELS[cosmetic.slot] : "Puntos"}
      title={prizeTitle(index!)}
      description={cosmetic ? `${cosmetic.description}${prize?.points ? ` +${prize.points} puntos.` : ""}` : "Para tu saldo de recompensas."}
      achievementLabel={current.title}
      achievementDescription={current.description}
      rewardPreview={<PrizePreview index={index!} />}
      pendingChests={pending.map((i) => ({ id: String(i), rarity: rewards[i].rarity }))}
      currentChestId={String(index)}
      onSelectChest={(id) => { const selected = Number(id); if (pending.includes(selected)) setIndex(selected); }}
      onRevealComplete={() => { if (index !== null) setOpened((previous) => previous.includes(index) ? previous : [...previous, index]); }}
      remainingCount={remaining}
      continueLabel={remaining > 0 ? "Abrir siguiente cofre →" : "Terminar y ver mis premios"}
      onContinue={next}
    /> : null}
  </main>;
}
