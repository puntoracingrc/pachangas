"use client";

import { useEffect, useRef, useState, type CSSProperties } from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { ThemeToggle } from "../theme-toggle";
import { rewards, PrizePreview } from "../chest-lab-rewards";
import { catalogEntry, PLAYER_COSMETIC_SLOT_LABELS } from "../player-cosmetics-catalog";
import palettes from "../reward-rarity-visuals.json";
import { unlockRewardAudio, createRouletteAudio, rewardSoundMuted } from "../reward-box-audio";
import { createStrip, type Loot } from "./roulette";
import { rouletteRequest, type RouletteSnapshot, type RouletteOperation, type RouletteChest as SavedChest } from "./server";
import { supabase } from "../supabaseClient";
import { googleAuthEntryHref } from "../google-auth-return";
import styles from "./page.module.css";
import { BatchSummary, type BatchSummaryData } from "./batch-summary";
import { useAnimatedPoints } from "./use-animated-points";

const RewardBox = dynamic(() => import("../reward-box-demo").then(m => m.RewardBoxDemo), { ssr: false });

const initialStrip = [0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 4, 0];
const random = () => crypto.getRandomValues(new Uint32Array(1))[0] / 4294967296;

export default function RouletteLab() {
  const rouletteSound = useRef<ReturnType<typeof createRouletteAudio> | null>(null);
  const [soundMuted, setSoundMuted] = useState(rewardSoundMuted);
  const [balance, setBalance] = useState(0);
  const [free, setFree] = useState(0);
  const [snapshot, setSnapshot] = useState<RouletteSnapshot | null>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");
  const [signedIn, setSignedIn] = useState(false);
  const userId = useRef<string | null>(null);
  const confirmedBalance = useRef(0);
  const pendingOperation = useRef<RouletteOperation | null>(null);
  const cost = snapshot?.cost ?? 15;
  const odds = snapshot?.odds ?? [60,25,10,4,1];
  const [phase, setPhase] = useState<"idle" | "spinning" | "won">("idle");
  const [strip, setStrip] = useState(initialStrip);
  const [winner, setWinner] = useState<number | null>(null);
  const [owned, setOwned] = useState<string[]>([]);
  const [latestId, setLatestId] = useState<string | null>(null);
  const [queue, setQueue] = useState<SavedChest[]>([]);
  const [active, setActive] = useState<{ chest: SavedChest; loot: Loot } | null>(null);
  const [summary, setSummary] = useState<BatchSummaryData | null>(null);
  const displayedBalance = useAnimatedPoints(balance, active !== null || summary !== null);
  const rouletteMachine = useRef<HTMLElement>(null);
  const returnFrame = useRef<number | null>(null);
  const pointsCounter = useRef<HTMLElement>(null);
  const previousDisplayedBalance = useRef(displayedBalance);
  useEffect(() => {
    const finishedAdding = displayedBalance > previousDisplayedBalance.current && displayedBalance === balance && active === null;
    previousDisplayedBalance.current = displayedBalance;
    if (!finishedAdding || !pointsCounter.current || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const colors = getComputedStyle(pointsCounter.current);
    const green = colors.getPropertyValue("--roulette-points").trim() || "#b7f452";
    const gold = colors.getPropertyValue("--roulette-gold").trim() || "#ffe39a";
    const glow = pointsCounter.current.animate([
      { color: green, textShadow: "0 0 0 transparent", transform: "scale(1)" },
      { color: gold, textShadow: "0 0 12px #ffd166, 0 0 30px #efb33c99", transform: "scale(1.06)", offset: 0.3 },
      { color: gold, textShadow: "0 0 16px #efb33c66", transform: "scale(1.02)", offset: 0.58 },
      { color: green, textShadow: "0 0 0 transparent", transform: "scale(1)" },
    ], { duration: 850, easing: "ease-out" });
    return () => glow.cancel();
  }, [displayedBalance, balance, active]);
  const pendingPoints = useRef(0);
  const granted = useRef(new Set<string>());
  const drawRef = useRef<SavedChest | null>(null);
  const [history, setHistory] = useState<number[]>([]);
  const track = useRef<HTMLDivElement>(null);
  const animation = useRef<Animation | null>(null);
  const lock = useRef(false);
  const token = useRef(0);
  const wonRef = useRef(0);
  const landingRef = useRef(0.5);
  useEffect(() => () => { token.current++; animation.current?.cancel(); rouletteSound.current?.dispose(); if (returnFrame.current !== null) cancelAnimationFrame(returnFrame.current); }, []);

  useEffect(() => {
    if (phase !== "spinning" || !track.current) return;
    const currentToken = token.current;
    const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
    const landingTransform = `translateX(calc(-40 * var(--step) - var(--tile) * ${landingRef.current}))`;
    const motion = track.current.animate([
      { transform: "translateX(calc(-3 * var(--step) - var(--tile) / 2))" },
      { transform: landingTransform },
    ], { duration: reduced ? 180 : 5600, easing: "cubic-bezier(.12,.72,.15,1)", fill: "forwards" });
    animation.current = motion;
    rouletteSound.current?.dispose();
    const sound = createRouletteAudio();
    rouletteSound.current = sound;
    let lastCell = 3;
    let soundFrame = 0;
    const syncTick = () => {
      const progress = motion.effect?.getComputedTiming().progress;
      if (typeof progress === "number") {
        const cell = Math.floor(3.5 + (40 + landingRef.current - 3.5) * progress);
        // One click per observed crossing, never replay missed clicks after a stalled frame.
        if (!reduced && cell > lastCell) sound.tick(progress);
        lastCell = cell;
      }
      if (motion.playState === "running") soundFrame = requestAnimationFrame(syncTick);
    };
    soundFrame = requestAnimationFrame(syncTick);
    void motion.finished.then(() => {
      if (currentToken !== token.current) return;
      if (track.current) track.current.style.transform = landingTransform;
      const chest = drawRef.current;
      setLatestId(chest?.id ?? null);
      if (chest) setQueue(previous => previous.some(item => item.id === chest.id) ? previous : [...previous, chest]);
      sound.finish(rewards[wonRef.current].rarity);
      setWinner(wonRef.current);
      setPhase("won");
      setHistory(previous => [wonRef.current, ...previous].slice(0, 6));
      lock.current = false;
    }).catch(() => {});
    return () => { cancelAnimationFrame(soundFrame); motion.cancel(); };
  }, [phase, strip]);

  function applySnapshot(next: RouletteSnapshot, showBalance = true) {
    setSnapshot(next); setFree(next.freeSpins); setOwned(next.owned); setQueue(next.queue); setHistory(next.history);
    confirmedBalance.current = next.balance;
    if (showBalance) setBalance(next.balance);
  }
  function storageKey() { return `pachangas:roulette-operation:${userId.current}`; }
  function remember(operation: RouletteOperation | null) {
    pendingOperation.current = operation;
    try { if (operation) sessionStorage.setItem(storageKey(), JSON.stringify(operation)); else sessionStorage.removeItem(storageKey()); } catch {}
  }
  async function request(action: RouletteOperation['action'], ids: string[] | null = null) {
    const operation = pendingOperation.current ?? { action, id: crypto.randomUUID(), ids };
    if (operation.action !== action || JSON.stringify(operation.ids) !== JSON.stringify(ids)) throw new Error('Recupera la operación pendiente antes de continuar.');
    remember(operation);
    try { const owner = userId.current; const response = await rouletteRequest(operation); if (owner !== userId.current) throw new Error('La sesión ha cambiado. Recarga tus recompensas.'); remember(null); return response; }
    catch (cause) {
      // A database error rolls back the transaction; transport failures retain the same operation id.
      if (cause && typeof cause === 'object' && 'code' in cause && cause.code) remember(null);
      throw cause;
    }
  }
  function restoreResponse(response: Awaited<ReturnType<typeof rouletteRequest>>) {
    if (response.entries?.length) {
      const entries = response.entries.filter(entry => !granted.current.has(entry.chest.id));
      const points = entries.reduce((sum, entry) => sum + entry.loot.points, 0);
      const previousPoints = pendingPoints.current;
      for (const entry of entries) granted.current.add(entry.chest.id);
      pendingPoints.current += points;
      applySnapshot(response.snapshot, false);
      setActive(null); setSummary({ entries, points, previousPoints });
    } else {
      applySnapshot(response.snapshot);
      if (response.chest) { setLatestId(response.chest.id); setWinner(response.chest.rarity); setPhase('won'); }
    }
  }
  function failure(cause: unknown) {
    const message = cause && typeof cause === 'object' && 'message' in cause ? String(cause.message) : '';
    if (cause && typeof cause === 'object' && 'code' in cause && cause.code) remember(null);
    setError(message.includes('Insufficient player points') ? 'No tienes puntos suficientes para otra tirada. Abre tus cofres pendientes o utiliza una gratuita.' : /^(Inicia sesión|Completa tu perfil|La ruleta no está|Cofre no encontrado)/.test(message) ? message : 'No se ha podido confirmar la operación. Pulsa Reintentar para recuperar tus recompensas.');
    lock.current = false; setBusy(false);
  }
  useEffect(() => {
    let alive = true;
    async function load(id: string | null) {
      userId.current = id; setSignedIn(Boolean(id)); setBusy(true); setError('');
      setBalance(0); setFree(0); setQueue([]); setOwned([]); setActive(null); setSummary(null); setSnapshot(null); setHistory([]); setLatestId(null); setWinner(null); setPhase('idle'); granted.current.clear(); pendingPoints.current = 0; pendingOperation.current = null; lock.current = false; token.current++; animation.current?.cancel();
      if (!id) { setBusy(false); return; }
      try {
        let stored: RouletteOperation | undefined;
        try { stored = JSON.parse(sessionStorage.getItem(`pachangas:roulette-operation:${id}`) ?? 'null') ?? undefined; } catch {}
        if (stored) pendingOperation.current = stored;
        const response = await rouletteRequest(stored);
        if (!alive || userId.current !== id) return;
        remember(null); restoreResponse(response); setBusy(false);
      } catch (cause) { if (alive) failure(cause); }
    }
    void supabase?.auth.getSession().then(({ data }) => load(data.session?.user.id ?? null));
    if (!supabase) queueMicrotask(() => { if (alive) { setBusy(false); setError('No se ha podido conectar con tus recompensas.'); } });
    const subscription = supabase?.auth.onAuthStateChange((_event, session) => {
      if ((session?.user.id ?? null) !== userId.current) void load(session?.user.id ?? null);
    });
    return () => { alive = false; subscription?.data.subscription.unsubscribe(); };
    // Initial hydration/auth changes only; mutation handlers own subsequent snapshots.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  async function recover() {
    if (lock.current) return;
    lock.current = true; setBusy(true); setError('');
    try {
      const response = await rouletteRequest(pendingOperation.current ?? undefined);
      remember(null); restoreResponse(response); lock.current = false; setBusy(false);
    } catch (cause) { failure(cause); }
  }
  async function spin() {
    if (lock.current || busy || !snapshot?.enabled || (!free && balance < cost)) return;
    unlockRewardAudio(); lock.current = true; setBusy(true); setError('');
    try {
      const response = await request('spin');
      if (!response.chest) throw new Error('No se ha podido recuperar el cofre.');
      applySnapshot({ ...response.snapshot, queue: response.snapshot.queue.filter(chest => chest.id !== response.chest!.id), history: response.snapshot.history.slice(1) });
      token.current++; animation.current?.cancel();
      const draw = createStrip(random, response.chest.rarity, response.snapshot.odds);
      wonRef.current = draw.winner; landingRef.current = draw.landing; drawRef.current = response.chest;
      setStrip(draw.strip); setWinner(null); setLatestId(null); setBusy(false); setPhase('spinning');
    } catch (cause) { failure(cause); }
  }
  const palette = winner === null ? null : palettes[rewards[winner].rarity];
  const loot = active?.loot;
  const cosmetic = catalogEntry(loot?.key);
  const lootTitle = loot?.duplicate || !cosmetic ? `+${loot?.points ?? 0} puntos` : cosmetic.name;
  const latest = queue.find(chest => chest.id === latestId);
  const locked = busy || phase === "spinning" || !snapshot || Boolean(error);
  async function openChest(chest: SavedChest) {
    if (lock.current || busy || granted.current.has(chest.id)) return;
    rouletteSound.current?.dispose(); unlockRewardAudio(); lock.current = true; setBusy(true); setError('');
    try {
      const response = await request('open', [chest.id]);
      const entry = response.entries?.[0];
      if (!entry) throw new Error('No se ha podido recuperar el premio.');
      applySnapshot(response.snapshot, false);
      if (!granted.current.has(chest.id)) { pendingPoints.current += entry.loot.points; granted.current.add(chest.id); }
      setActive(entry); lock.current = false; setBusy(false);
    } catch (cause) { failure(cause); }
  }
  async function openAll() {
    if (lock.current || busy || summary || !queue.length) return;
    rouletteSound.current?.dispose(); lock.current = true; setBusy(true); setError('');
    try {
      const response = await request('open_all');
      const entries = response.entries ?? [];
      const previousPoints = pendingPoints.current;
      for (const entry of entries) granted.current.add(entry.chest.id);
      pendingPoints.current += response.points ?? 0;
      applySnapshot(response.snapshot, false); setActive(null);
      setSummary({ entries, points: response.points ?? 0, previousPoints });
      lock.current = false; setBusy(false);
    } catch (cause) { failure(cause); }
  }
  function returnToRoulette() {
    setSoundMuted(rewardSoundMuted());
    pendingPoints.current = 0;
    setActive(null);
    setSummary(null);
    returnFrame.current = requestAnimationFrame(() => {
      // Wait for the modal to restore document scrolling before framing the balance.
      rouletteMachine.current?.scrollIntoView({ block: "start", behavior: "instant" });
      pointsCounter.current?.focus({ preventScroll: true });
      setBalance(confirmedBalance.current);
      returnFrame.current = null;
    });
  }
  return <main className={styles.page}>
    <header className={styles.top}><Link href="/">← Volver a la app</Link><span>PACHANGAS IQ · RECOMPENSAS</span><div className={styles.topActions}><ThemeToggle compact defaultPreference="dark"/><button type="button" aria-pressed={!soundMuted} onClick={() => { unlockRewardAudio(); const sound = rouletteSound.current ?? createRouletteAudio(); rouletteSound.current = sound; sound.setMuted(!soundMuted); setSoundMuted(!soundMuted); }}>{soundMuted ? "Activar sonido" : "Silenciar sonido"}</button></div></header>
    <section className={styles.intro}><h1>Ruleta de premios</h1></section>
    <div style={{ minHeight: "4.5rem" }}>
    {!signedIn && !busy && <p><Link href={googleAuthEntryHref('/ruleta')}>Inicia sesión para ver tus premios</Link></p>}
    {busy && <p role="status">Cargando tus recompensas…</p>}
    {error && <p role="alert">{error} <button onClick={recover} disabled={busy}>Reintentar</button></p>}
    {signedIn && snapshot && <p>{free} {free === 1 ? 'tirada gratis disponible' : 'tiradas gratis disponibles'} · Se guardan hasta que las uses.</p>}
    </div>
    <section ref={rouletteMachine} className={styles.machine} aria-label="Ruleta de cofres" aria-busy={phase === "spinning"} style={{ "--won": palette?.accent ?? "#b7f452" } as CSSProperties}>
      <div className={styles.machineHeader}><span>Tus puntos</span><strong tabIndex={-1} ref={pointsCounter} data-counting={displayedBalance < balance ? "up" : displayedBalance > balance ? "down" : undefined} aria-label={`${balance} puntos`}><span aria-hidden="true">{displayedBalance} <small>puntos</small></span></strong></div>
      <div className={styles.window}>
        <div className={styles.marker} aria-hidden="true"/>
        <div ref={track} className={styles.track} aria-hidden="true">
          {strip.map((rarity, i) => { const p = palettes[rewards[rarity].rarity]; return <div key={i} data-selected={phase === "won" && i === 40 || undefined} className={styles.tile} style={{ "--accent": p.accent } as CSSProperties}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`/models/rewards/thumbnails/cofre-${rewards[rarity].rarity}.png`} alt="" width="160" height="125" draggable={false}/><strong>{p.label}</strong><span>{String(rarity + 1).padStart(2, "0")}</span>
          </div>; })}
        </div>
      </div>
      <div className={styles.chestLegend} aria-label="Probabilidades de cada cofre">
        {rewards.map((reward, i) => <span key={reward.rarity}><i aria-hidden="true" style={{ background: palettes[reward.rarity].accent }}/>{palettes[reward.rarity].label} <strong>{odds[i]} %</strong></span>)}
      </div>
      <div className={styles.result} role="status" aria-live="polite">{palette ? <><strong>Cofre {palette.label.toLowerCase()}</strong><span>{latest ? "Guardado en tus cofres pendientes. Puedes abrirlo ahora o más tarde." : "Premio revelado. Puedes volver a girar."}</span></> : <><strong>{phase === "spinning" ? "La ruleta está girando…" : "¿Qué cofre te tocará?"}</strong><span>{phase === "spinning" ? "Se detendrá bajo el marcador central." : "Los comunes salen más a menudo. Los legendarios, solo un 1 %."}</span></>}</div>
      {latest ? <div className={styles.actions}><button className={styles.primary} disabled={locked} onClick={() => openChest(latest)}>Abrir este cofre →</button><button className={styles.paid} disabled={locked || !snapshot?.enabled || (!free && balance < cost)} onClick={() => spin()}>Abrir después · {free ? "girar gratis" : `girar por ${cost} puntos`}</button></div> : <div className={styles.actions} style={{ visibility: locked ? "hidden" : "visible" }}><button className={styles.primary} disabled={locked || !snapshot?.enabled || (!free && balance < cost)} onClick={() => spin()}>{free ? "Girar gratis" : `Girar · ${cost} puntos`}</button></div>}
    </section>
    <section id="cofres" className={styles.saved} aria-label="Cofres acumulados">
      <div><h2>{queue.length} {queue.length === 1 ? "cofre pendiente" : "cofres pendientes"}</h2><p>{balance < cost && !free && queue.length ? "No tienes puntos para otra tirada. Abre tus cofres: algunos pueden darte puntos para seguir." : "Guárdalos y sigue girando, o elige cuál abrir. Los puntos ganados se suman cuando vuelves de abrir los cofres."}</p></div>
      <button className={styles.primary} disabled={locked || !queue.length} onClick={() => openChest(queue[0])}>Abrir cofres acumulados{queue.length ? ` (${queue.length})` : ""} →</button>
      <button className={styles.paid} disabled={locked || !queue.length} onClick={openAll}>Abrir todo</button>
      <div className={styles.savedQueue}>{queue.map((chest, i) => <button key={chest.id} disabled={locked} onClick={() => openChest(chest)} style={{ "--accent": palettes[rewards[chest.rarity].rarity].accent } as CSSProperties}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={`/models/rewards/thumbnails/cofre-${rewards[chest.rarity].rarity}.png`} alt="" width={80} height={64}/><span>{i + 1} · {palettes[rewards[chest.rarity].rarity].label}</span>
      </button>)}</div>
    </section>
    <details className={styles.contents}><summary>Premios y tiradas gratuitas</summary><p>Todos los objetos son estéticos. Si ya tienes el cosmético, recibes puntos. Las probabilidades son iguales para todos.</p><div>{rewards.map((r, i) => <article key={r.rarity}><strong style={{ "--accent": palettes[r.rarity].accent } as CSSProperties}>{palettes[r.rarity].label}</strong>{snapshot?.pools.filter(p => p.rarity === i).map((p, index) => <span key={index}>{p.weight} % · {p.key ? catalogEntry(p.key)?.name ?? p.key : 'Puntos'}{p.max > 0 ? ` · ${p.min}–${p.max} puntos` : ''}{p.key ? ` · repetido: +${p.duplicatePoints} puntos` : ''}</span>)}</article>)}</div><p>Una tirada al completar el test inicial y otra al completar el avanzado. Además, una semanal si has jugado un partido confirmado en los últimos 30 días. Se acumulan: al dejar de jugar conservas las que ya tienes.</p></details>
    <section className={styles.collection}><div><h2>Tu colección</h2><p>{owned.length ? owned.map(key => catalogEntry(key)?.name).join(" · ") : "Aún no tienes cosméticos."}</p></div></section>
    {history.length > 0 && <section className={styles.history}><h2>Tus últimos cofres</h2><div>{history.map((r, i) => <span key={i} style={{ "--accent": palettes[rewards[r].rarity].accent } as CSSProperties}>{palettes[rewards[r].rarity].label}</span>)}</div></section>}
    {active && loot && <RewardBox key={active.chest.id} open rarity={rewards[active.chest.rarity].rarity} onClose={returnToRoulette} title={lootTitle} description={loot.duplicate ? `${cosmetic?.name} repetido. Convertido en ${loot.points} puntos.` : (cosmetic ? `${cosmetic.description}${loot.points ? ` Además, +${loot.points} puntos.` : ""}` : "")} eyebrow={loot.duplicate ? "Cosmético repetido" : cosmetic ? PLAYER_COSMETIC_SLOT_LABELS[cosmetic.slot] : "Puntos"} rewardPreview={<PrizePreview index={active.chest.rarity} prizeOverride={{ key: loot.duplicate ? null : loot.key, points: loot.points, color: palettes[rewards[active.chest.rarity].rarity].accent }}/>} 
      secondaryActionProminent secondaryActionLabel={queue.length ? "Abrir todo" : undefined} onSecondaryAction={openAll} secondaryActionDisabled={busy}
      pendingChests={queue.map(chest => ({ id: String(chest.id), rarity: rewards[chest.rarity].rarity }))} currentChestId={String(active.chest.id)} onSelectChest={id => { const chest = queue.find(item => String(item.id) === id); if (chest) openChest(chest); }} remainingCount={queue.length}
      continueLabel={queue.length ? "Abrir siguiente cofre →" : "Volver a la ruleta"} onContinue={() => { if (queue.length) openChest(queue[0]); else returnToRoulette(); }}/>}
    {summary && <BatchSummary data={summary} onAccept={returnToRoulette}/>}

  </main>;
}
