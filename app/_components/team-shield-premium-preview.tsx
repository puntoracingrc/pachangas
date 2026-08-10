"use client";

import type { TeamShieldConfig, TeamShieldRenderableItem } from "../team-shield-contract";
import { TEAM_SHIELD_PREMIUM_BALL_KEY } from "../team-shield-premium-assets";
import { TeamShieldView } from "./team-shield-view";
import styles from "./team-shield-premium-preview.module.css";
import { useTeamShieldPremiumMotion } from "./use-team-shield-premium-motion";

const STATUS_LABELS = {
  active: "Movimiento activo",
  denied: "Permiso denegado · versión estática",
  off: "Movimiento desactivado",
  reduced: "Movimiento reducido · versión estática",
  unavailable: "Sensor no disponible · versión estática",
} as const;

export function TeamShieldPremiumPreview({
  catalog,
  className = "",
  config,
  label,
}: {
  catalog?: readonly TeamShieldRenderableItem[];
  className?: string;
  config: TeamShieldConfig;
  label?: string;
}) {
  const {
    activate,
    deactivate,
    setViewportNode,
    status,
    visual,
  } = useTeamShieldPremiumMotion();
  const premiumBallEquipped = config.primarySymbolKey === TEAM_SHIELD_PREMIUM_BALL_KEY;

  return (
    <div className={styles.preview} data-premium-ball={premiumBallEquipped} ref={setViewportNode}>
      <TeamShieldView
        catalog={catalog}
        className={className}
        config={config}
        label={label}
        motion={status === "reduced" ? "reduced" : "auto"}
        premiumBallMotion={premiumBallEquipped ? visual : undefined}
      />
      {premiumBallEquipped ? (
        <div className={styles.controls}>
          <button
            disabled={status === "denied" || status === "reduced" || status === "unavailable"}
            onClick={() => void (status === "active" ? deactivate() : activate())}
            type="button"
          >
            {status === "active" ? "Desactivar movimiento" : "Activar movimiento"}
          </button>
          <small aria-live="polite">{STATUS_LABELS[status]}</small>
        </div>
      ) : null}
    </div>
  );
}
