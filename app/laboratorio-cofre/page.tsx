"use client";

import { useState } from "react";
import dynamic from "next/dynamic";
import { catalogEntry, PLAYER_COSMETIC_SLOT_LABELS } from "../player-cosmetics-catalog";
import { unlockRewardAudio } from "../reward-box-audio";
import rewardRarityVisuals from "../reward-rarity-visuals.json";
import { rewards, prizes, prizeTitle, PrizePreview } from "../chest-lab-rewards";

const RewardBoxDemo = dynamic(() => import("../reward-box-demo").then((module) => module.RewardBoxDemo), { ssr: false });

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
