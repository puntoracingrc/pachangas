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

export function MarketFilters({ activeTab, draft, onChange, onReset }: {
  activeTab: "equipos" | "jugadores" | "partidos";
  draft: MarketFilterDraft;
  onChange: (patch: Partial<MarketFilterDraft>) => void;
  onReset: () => void;
}) {
  return (
    <section className={styles.inlineFilters} aria-label="Filtros de mercado">
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
              <select value={draft.minRating ?? ""} onChange={(event) => onChange({ minRating: event.target.value === "" ? null : Number(event.target.value) })}>
                <option value="">Todos</option>
                {Array.from({ length: 101 }, (_, level) => <option key={level} value={level}>{level}</option>)}
              </select>
            </label>
            <label>
              Nivel máximo
              <select value={draft.maxRating ?? ""} onChange={(event) => onChange({ maxRating: event.target.value === "" ? null : Number(event.target.value) })}>
                <option value="">Todos</option>
                {Array.from({ length: 101 }, (_, level) => <option key={level} value={level}>{level}</option>)}
              </select>
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

      <button className={styles.clearButton} type="button" onClick={onReset}>Restablecer</button>
    </section>
  );
}
