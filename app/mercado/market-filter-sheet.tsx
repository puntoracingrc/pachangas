"use client";

import type { MarketDayFilter, MarketRouteFilters } from "./market-ui-contract";
import { MARKET_DAY_FILTERS } from "./market-ui-contract";
import styles from "./marketplace-v3d.module.css";

export type MarketFilterDraft = MarketRouteFilters & {
  approval: "all" | "instant" | "manual";
  goalkeeperOnly: boolean;
  openSlotsOnly: boolean;
};

const modalities = [
  ["Todas", "Todas"],
  ["futbol7", "Fútbol 7"],
  ["sala", "Fútbol sala"],
  ["futbol11", "Fútbol 11"],
] as const;

const positions = ["Todas", "Portero", "Defensa", "Medio", "Ataque"];

export function MarketFilterSheet({
  activeTab,
  draft,
  onApply,
  onChange,
  onClose,
  onReset,
  resultCount,
}: {
  activeTab: "equipos" | "jugadores" | "partidos";
  draft: MarketFilterDraft;
  onApply: () => void;
  onChange: (patch: Partial<MarketFilterDraft>) => void;
  onClose: () => void;
  onReset: () => void;
  resultCount: number;
}) {
  const resultLabel = activeTab === "partidos" ? "partidos" : activeTab === "jugadores" ? "jugadores" : "equipos";
  return (
    <div className={`${styles.filterBackdrop} market-filter-backdrop-v3d`} role="presentation" onMouseDown={(event) => {
      if (event.target === event.currentTarget) onClose();
    }}>
      <section className={styles.filterSheet} role="dialog" aria-modal="true" aria-labelledby="market-filter-title">
        <header>
          <div><span>Refina la búsqueda</span><h2 id="market-filter-title">Filtros de {resultLabel}</h2></div>
          <button className={styles.iconButton} type="button" onClick={onClose} aria-label="Cerrar filtros">×</button>
        </header>

        <div className={styles.filterGrid}>
          <label>
            Día
            <select value={draft.day} onChange={(event) => onChange({ day: event.target.value as MarketDayFilter })}>
              {MARKET_DAY_FILTERS.map((day) => <option key={day} value={day}>{day}</option>)}
            </select>
          </label>
          <label>
            Modalidad
            <select value={draft.modality} onChange={(event) => onChange({ modality: event.target.value })}>
              {modalities.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
          </label>
          <label>
            Radio
            <select value={draft.radiusKm} onChange={(event) => onChange({ radiusKm: Number(event.target.value) })}>
              {[5, 10, 20, 30, 50, 75, 100].map((radius) => <option key={radius} value={radius}>{radius} km</option>)}
            </select>
          </label>

          {activeTab !== "equipos" ? (
            <label>
              Posición
              <select value={draft.position} onChange={(event) => onChange({ position: event.target.value })}>
                {positions.map((position) => <option key={position} value={position}>{position}</option>)}
              </select>
            </label>
          ) : null}

          {activeTab === "partidos" ? (
            <>
              <label>
                Precio máximo
                <input min="0" inputMode="decimal" type="number" value={draft.maxPrice ?? ""} onChange={(event) => onChange({ maxPrice: event.target.value === "" ? null : Number(event.target.value) })} placeholder="Sin límite" />
              </label>
              <label>
                Aprobación
                <select value={draft.approval} onChange={(event) => onChange({ approval: event.target.value as MarketFilterDraft["approval"] })}>
                  <option value="all">Cualquiera</option>
                  <option value="manual">Manual</option>
                  <option value="instant">Inmediata</option>
                </select>
              </label>
              <label className={styles.toggleField}>
                <input type="checkbox" checked={draft.openSlotsOnly} onChange={(event) => onChange({ openSlotsOnly: event.target.checked })} />
                <span>Solo con plazas</span>
              </label>
            </>
          ) : null}

          {activeTab !== "partidos" ? (
            <>
              <label>
                Nivel mínimo
                <input min="0" max="100" inputMode="numeric" type="number" value={draft.minRating ?? ""} onChange={(event) => onChange({ minRating: event.target.value === "" ? null : Number(event.target.value) })} placeholder="Todos" />
              </label>
              <label>
                Nivel máximo
                <input min="0" max="100" inputMode="numeric" type="number" value={draft.maxRating ?? ""} onChange={(event) => onChange({ maxRating: event.target.value === "" ? null : Number(event.target.value) })} placeholder="Todos" />
              </label>
            </>
          ) : null}

          {activeTab === "jugadores" ? (
            <label className={styles.toggleField}>
              <input type="checkbox" checked={draft.goalkeeperOnly} onChange={(event) => onChange({ goalkeeperOnly: event.target.checked })} />
              <span>Solo porteros</span>
            </label>
          ) : null}
        </div>

        <footer>
          <button className={styles.secondaryButton} type="button" onClick={onReset}>Restablecer</button>
          <button className={styles.primaryButton} type="button" onClick={onApply}>Mostrar {resultCount} {resultLabel}</button>
        </footer>
      </section>
    </div>
  );
}
