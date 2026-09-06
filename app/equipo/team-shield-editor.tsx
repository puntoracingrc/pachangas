"use client";

import { CosmeticCategoryNav, CosmeticEditorShell, CosmeticOptionSelector, EditorActions, MaterialSwatch, UnsavedChanges } from "../_components/cosmetics-editor";
import { TeamShieldView } from "../_components/team-shield-view";
import type { TeamShieldConfig, TeamShieldCosmeticSlot } from "../team-shield-contract";
import type { CrestCatalogItem } from "../team-identity-contract";
import styles from "./identidad/page.module.css";

const teamShieldCategoryLabels: Record<TeamShieldCosmeticSlot, string> = {
  background: "Fondo",
  border: "Borde",
  bottom_ornament: "Base",
  effect: "Efecto",
  pattern: "Trama",
  primary_symbol: "Símbolo",
  secondary_symbol: "Símbolo 2",
  shape: "Forma",
  side_ornament: "Laterales",
  top_ornament: "Corona",
};

const teamShieldCategories = Object.keys(teamShieldCategoryLabels) as TeamShieldCosmeticSlot[];

const rarityLabels: Record<CrestCatalogItem["rarity"], string> = {
  common: "Común",
  epic: "Épico",
  legendary: "Legendario",
  rare: "Raro",
  uncommon: "Poco común",
};

export function teamShieldItemsForSlot(catalog: CrestCatalogItem[], slot: TeamShieldCosmeticSlot) {
  if (slot === "secondary_symbol") return catalog.filter((item) => item.family === "symbol");
  return catalog.filter((item) => item.slot === slot);
}

function selectedTeamShieldKeys(config: TeamShieldConfig, slot: TeamShieldCosmeticSlot) {
  const keys: Record<TeamShieldCosmeticSlot, string | null> = {
    background: config.backgroundKey,
    border: config.borderKey,
    bottom_ornament: config.bottomOrnamentKey,
    effect: config.effectKey,
    pattern: config.patternKey,
    primary_symbol: config.primarySymbolKey,
    secondary_symbol: config.secondarySymbolKey,
    shape: config.shapeKey,
    side_ornament: config.sideOrnamentKey,
    top_ornament: config.topOrnamentKey,
  };
  return keys[slot] ? [keys[slot] as string] : [];
}

function updateTeamShieldSlot(
  config: TeamShieldConfig,
  slot: TeamShieldCosmeticSlot,
  key: string | null,
): TeamShieldConfig {
  if (slot === "shape" && key) return { ...config, shapeKey: key };
  if (slot === "border" && key) return { ...config, borderKey: key };
  if (slot === "background" && key) return { ...config, backgroundKey: key };
  if (slot === "pattern") return { ...config, patternKey: key };
  if (slot === "primary_symbol" && key) return { ...config, primarySymbolKey: key };
  if (slot === "secondary_symbol") return { ...config, secondarySymbolKey: key };
  if (slot === "top_ornament") return { ...config, topOrnamentKey: key };
  if (slot === "side_ornament") return { ...config, sideOrnamentKey: key };
  if (slot === "bottom_ornament") return { ...config, bottomOrnamentKey: key };
  if (slot === "effect") return { ...config, effectKey: key };
  return config;
}

export function TeamShieldCosmeticsEditor({
  activeCategory,
  busy,
  canSave,
  catalog,
  config,
  dirty,
  isOnline,
  onCategoryChange,
  onChange,
  onReset,
  onSave,
  revision,
}: {
  activeCategory: TeamShieldCosmeticSlot;
  busy: boolean;
  canSave: boolean;
  catalog: CrestCatalogItem[];
  config: TeamShieldConfig;
  dirty: boolean;
  isOnline: boolean;
  onCategoryChange: (slot: TeamShieldCosmeticSlot) => void;
  onChange: (config: TeamShieldConfig) => void;
  onReset: () => void;
  onSave: () => void;
  revision: number;
}) {
  const colors = catalog.filter((item) => item.family === "color");
  const items = teamShieldItemsForSlot(catalog, activeCategory);
  const selectedKeys = selectedTeamShieldKeys(config, activeCategory);
  const counts = Object.fromEntries(teamShieldCategories.map((slot) => [
    slot,
    teamShieldItemsForSlot(catalog, slot).filter((item) => item.acquiredAt && !item.seenAt).length,
  ])) as Record<TeamShieldCosmeticSlot, number>;
  const optional = activeCategory === "effect" || activeCategory === "pattern"
    || activeCategory === "secondary_symbol" || activeCategory === "top_ornament"
    || activeCategory === "side_ornament" || activeCategory === "bottom_ornament";

  return (
    <CosmeticEditorShell
      className={styles.teamCosmeticEditor}
      preview={(
        <div className={styles.previewStage}>
          <TeamShieldView catalog={catalog} className={styles.identityShield} config={config} />
          <div>
            <span>{dirty ? "Vista previa" : "Escudo del equipo"}</span>
            <strong>{config.initials}</strong>
            <small>{dirty ? "Cambios sin guardar" : `Versión ${revision}`}</small>
          </div>
        </div>
      )}
      actions={(
        <>
          <EditorActions
            busy={busy}
            onPrimary={onSave}
            onReset={onReset}
            primaryDisabled={!canSave || !dirty || !isOnline}
            primaryLabel={!canSave ? "Solo administradores pueden guardar" : busy ? "Guardando…" : isOnline ? "Guardar escudo" : "Sin conexión"}
            resetLabel="Deshacer cambios"
          />
          <UnsavedChanges dirty={dirty} synchronizedLabel="Escudo sincronizado" />
        </>
      )}
    >
      <CosmeticCategoryNav
        active={activeCategory}
        ariaLabel="Partes del escudo"
        items={teamShieldCategories.map((slot) => ({
          count: counts[slot],
          key: slot,
          label: teamShieldCategoryLabels[slot],
        }))}
        onChange={onCategoryChange}
      />
      <div className={styles.identityFields}>
        <label>
          Iniciales
          <input
            maxLength={4}
            value={config.initials}
            onChange={(event) => onChange({
              ...config,
              initials: event.target.value.toUpperCase().replace(/\s/g, ""),
            })}
          />
        </label>
        <label>
          Año
          <input
            inputMode="numeric"
            maxLength={4}
            placeholder="Opcional"
            value={config.foundationYear}
            onChange={(event) => onChange({
              ...config,
              foundationYear: event.target.value.replace(/\D/g, "").slice(0, 4),
            })}
          />
        </label>
      </div>
      <div className={styles.teamColorRows}>
        {(["primaryColorKey", "secondaryColorKey"] as const).map((field) => (
          <div className={styles.teamColorRow} key={field}>
            <span>{field === "primaryColorKey" ? "Principal" : "Secundario"}</span>
            <div>
              {colors.map((item) => (
                <button
                  aria-label={`${field === "primaryColorKey" ? "Color principal" : "Color secundario"} ${item.name}`}
                  aria-pressed={config[field] === item.key}
                  className={config[field] === item.key ? styles.activeSwatch : ""}
                  key={`${field}-${item.key}`}
                  type="button"
                  onClick={() => onChange({ ...config, [field]: item.key })}
                >
                  <MaterialSwatch
                    color={typeof item.render.hex === "string" ? item.render.hex : null}
                    material={item.material ?? null}
                  />
                </button>
              ))}
            </div>
          </div>
        ))}
      </div>
      {activeCategory === "primary_symbol" ? (
        <div className={styles.symbolControls}>
          <label>
            Tamaño
            <span>
              <button type="button" onClick={() => onChange({ ...config, primarySymbolScale: Math.max(0.8, config.primarySymbolScale - 0.05) })}>−</button>
              <strong>{Math.round(config.primarySymbolScale * 100)}%</strong>
              <button type="button" onClick={() => onChange({ ...config, primarySymbolScale: Math.min(1.2, config.primarySymbolScale + 0.05) })}>+</button>
            </span>
          </label>
          <label>
            Giro
            <span>
              <button type="button" onClick={() => onChange({ ...config, primarySymbolRotation: Math.max(-12, config.primarySymbolRotation - 3) })}>−</button>
              <strong>{config.primarySymbolRotation}°</strong>
              <button type="button" onClick={() => onChange({ ...config, primarySymbolRotation: Math.min(12, config.primarySymbolRotation + 3) })}>+</button>
            </span>
          </label>
        </div>
      ) : null}
      {items.length ? (
        <CosmeticOptionSelector
          items={items.map((item) => ({
            key: item.key,
            material: item.material,
            meta: `${rarityLabels[item.rarity]}${item.collection ? ` · ${item.collection.replaceAll("_", " ")}` : ""}`,
            name: item.name,
            new: Boolean(item.acquiredAt && !item.seenAt),
          }))}
          noneLabel={optional ? "Ninguno" : undefined}
          onChange={(key) => onChange(updateTeamShieldSlot(config, activeCategory, key))}
          selectedKeys={selectedKeys}
        />
      ) : <p className={styles.emptyCategory}>No hay piezas disponibles en esta categoría.</p>}
    </CosmeticEditorShell>
  );
}

