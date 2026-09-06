"use client";

import { useEffect, useState } from "react";
import { PLAYER_COSMETIC_RARITY_LABELS } from "../player-cosmetics-catalog";
import type { PlayerCosmeticRarity } from "../player-cosmetics-contract";
import { supabase } from "../supabaseClient";
import { achievementProgress, type AchievementDefinition, type AchievementGrant, type AchievementStats } from "./achievement-gallery-model";
import styles from "./achievement-gallery.module.css";

const rarities: PlayerCosmeticRarity[] = ["common", "uncommon", "rare", "epic", "legendary"];
const captions = ["Tus primeros pasos", "Empiezas a destacar", "Dejas tu huella", "Al alcance de pocos", "Una trayectoria excepcional"];
type Collection = { profileId?: string; groupId?: string; definitions: AchievementDefinition[]; stats: AchievementStats[]; grants: AchievementGrant[] };

function Medal({ unlocked }: { unlocked: boolean }) {
  return <svg className={styles.medal} viewBox="0 0 100 108" aria-hidden="true">
    <path className={styles.ribbon} d="m28 64-9 39 20-11 11 9 11-9 20 11-9-39" />
    <path className={styles.shield} d="M50 4 85 18v32c0 21-19 35-35 43C34 85 15 71 15 50V18Z" />
    <path className={styles.inset} d="m50 12 27 12v26c0 16-14 28-27 35-13-7-27-19-27-35V24Z" />
    {unlocked ? <path className={styles.symbol} d="m33 47 12 12 23-25" /> : <path className={styles.star} d="m50 28 7 14 16 2-12 12 3 16-14-8-14 8 3-16-12-12 16-2Z" />}
  </svg>;
}

export function AchievementGallery({ profileId }: { profileId: string }) {
  return <AchievementCollection key={profileId} subject="player" subjectId={profileId} />;
}

export function TeamAchievementGallery({ groupId }: { groupId: string }) {
  return <AchievementCollection key={groupId} subject="team" subjectId={groupId} />;
}

function AchievementCollection({ subject, subjectId }: { subject: "player" | "team"; subjectId: string }) {
  const team = subject === "team";
  const [collection, setCollection] = useState<Collection | null>(null);
  const [error, setError] = useState(false);
  const [retry, setRetry] = useState(0);
  const [rarity, setRarity] = useState<PlayerCosmeticRarity | "all">("all");
  const [statusFilter, setStatusFilter] = useState<"all" | "unlocked" | "pending">("all");
  useEffect(() => {
    const client = supabase;
    let generation = 0;
    let disposed = false;
    async function load() {
      const request = ++generation;
      try {
        if (!client) throw new Error("Unavailable");
        const { data, error: requestError } = team
          ? await client.rpc("get_pachanga_team_achievement_gallery_v1", { target_group_id: subjectId })
          : await client.rpc("get_my_pachanga_achievement_gallery_v1");
        if (disposed || request !== generation) return;
        if (requestError || !data || (team ? data.groupId : data.profileId) !== subjectId
          || !Array.isArray(data.definitions) || !Array.isArray(data.stats) || !Array.isArray(data.grants)) {
          setCollection(null);
          setError(true);
          return;
        }
        setCollection(data as Collection);
        setError(false);
      } catch { if (!disposed && request === generation) { setCollection(null); setError(true); } }
    }
    void load();
    const channel = team ? client?.channel(`team-achievements-${subjectId}`).on("postgres_changes", {
      event: "*", schema: "public", table: "pachanga_progression_group_state", filter: `group_id=eq.${subjectId}`,
    }, load).subscribe() : null;
    const auth = client?.auth.onAuthStateChange(() => queueMicrotask(() => { if (!disposed) void load(); }));
    window.addEventListener("focus", load);
    window.addEventListener("online", load);
    return () => { disposed = true; if (channel) void client?.removeChannel(channel); auth?.data.subscription.unsubscribe(); window.removeEventListener("focus", load); window.removeEventListener("online", load); };
  }, [subjectId, team, retry]);

  const data = (team ? collection?.groupId : collection?.profileId) === subjectId ? collection : null;
  const entries = data?.definitions.map(definition => ({ ...definition, ...achievementProgress(definition, data.stats, data.grants) })) ?? [];
  const unlocked = entries.filter(item => item.unlocked).length;
  return <section className={styles.gallery} aria-label={team ? "Colección de logros del equipo" : "Colección de logros"}>
    <header className={styles.header}>
      <div><span className={styles.eyebrow}>{team ? "Vuestra historia, logro a logro" : "Tu próxima conquista"}</span><h2>{team ? "Logros del equipo" : "Logros por descubrir"}</h2><p>{team ? "Lo que habéis conseguido juntos y los desafíos que os esperan. Cada partido cuenta." : "Cada partido cuenta. Descubre qué puedes conseguir y sigue tu progreso."}</p></div>
      {data && !error ? <div className={styles.total}><strong>{unlocked}<span> / {entries.length}</span></strong><span>logros conseguidos</span>{team ? <span>{entries.length - unlocked} por conseguir</span> : null}</div> : null}
    </header>
    {error ? <div className={styles.message} role="status">{team ? "No hemos podido actualizar los logros del equipo." : "No hemos podido actualizar tus logros."} <button type="button" onClick={() => setRetry(value => value + 1)}>Volver a intentar</button></div> : !data ? <p className={styles.message} role="status">{team ? "Cargando los logros del equipo…" : "Cargando tu colección de logros…"}</p> : <>
      <div className={styles.filters}>
        <div className={styles.rarityFilters} aria-label="Filtrar logros por rareza">
          <button type="button" aria-pressed={rarity === "all"} onClick={() => setRarity("all")}>Todos</button>
          {rarities.map(value => <button type="button" key={value} data-rarity={value} aria-pressed={rarity === value} onClick={() => setRarity(value)}><i aria-hidden="true" />{PLAYER_COSMETIC_RARITY_LABELS[value]}</button>)}
        </div>
        {team ? <div className={styles.rarityFilters} role="group" aria-label="Filtrar por estado">
          {([['all', 'Todos los logros'], ['unlocked', 'Conseguidos'], ['pending', 'Por conseguir']] as const).map(([value, label]) => <button key={value} type="button" aria-pressed={statusFilter === value} onClick={() => setStatusFilter(value)}>{label}</button>)}
        </div> : <label className={styles.pending}><input type="checkbox" checked={statusFilter === "pending"} onChange={event => setStatusFilter(event.target.checked ? "pending" : "all")} />Por conseguir</label>}
      </div>
      {rarities.filter(value => rarity === "all" || rarity === value).map((value) => {
        const group = entries.filter(item => item.rarity === value);
        const visible = group.filter(item => statusFilter === "all" || (statusFilter === "unlocked" ? item.unlocked : !item.unlocked));
        return <section key={value} data-rarity={value} className={styles.group} aria-label={`Logros: ${PLAYER_COSMETIC_RARITY_LABELS[value]}`}>
          <header className={styles.groupHeader}><div><h3>{PLAYER_COSMETIC_RARITY_LABELS[value]}</h3><p>{team ? ["Los primeros pasos juntos", "Un equipo que empieza a destacar", "Dejáis vuestra huella", "Hazañas que os hacen únicos", "Una historia para recordar"][rarities.indexOf(value)] : captions[rarities.indexOf(value)]}</p></div><span>{group.filter(item => item.unlocked).length} / {group.length}</span></header>
          <div className={styles.cards}>{visible.map(item => <article className={styles.card} data-unlocked={item.unlocked} key={item.id}>
            <div className={styles.cardTop}><span>{item.match_scope === "external" ? "Retos" : item.match_scope === "internal" ? "Pachangas" : "Todos los partidos"}</span><span className={styles.status}>{item.unlocked ? "✓ Conseguido" : "Por conseguir"}</span></div>
            <Medal unlocked={item.unlocked} />
            <h4>{item.title}</h4><p className={styles.description}>{item.description}</p>
            <div className={styles.progressArea}>
              <div><span>{item.unlocked ? item.repeatable ? `${item.occurrences} ${item.occurrences === 1 ? "vez conseguido" : "veces conseguido"}` : (team ? "Ya forma parte de vuestra historia" : "Ya forma parte de tu colección") : (team ? "Progreso del equipo" : "Tu progreso")}</span><strong>{item.current == null ? "—" : `${Math.min(item.current, item.target)} / ${item.target}`}</strong></div>
              {item.current != null ? <progress aria-label={`Progreso de ${item.title}`} max={100} value={item.percent} /> : null}
              {item.repeatable ? <small>{team ? "Podéis conseguirlo más de una vez" : "Puedes conseguirlo más de una vez"}</small> : null}
            </div>
          </article>)}</div>
          {!visible.length ? <p className={styles.message}>{group.length ? statusFilter === "unlocked" ? "Todavía no hay logros conseguidos de esta rareza." : team ? "¡Habéis conseguido todos los logros de esta rareza!" : "¡Ya has conseguido todos los logros de esta rareza!" : "Todavía no hay logros de esta rareza."}</p> : null}
        </section>;
      })}
    </>}
  </section>;
}
