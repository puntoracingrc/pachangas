import Link from "next/link";
import type { ReactNode } from "react";
import styles from "./official-home-game-dashboard.module.css";

export type OfficialHomeAction = {
  detail: string;
  eyebrow: string;
  href?: string;
  label: string;
  onClick?: () => void;
};

export type OfficialHomeMetric = {
  label: string;
  value: ReactNode;
};

export type OfficialUpcomingMatch = {
  context: string;
  date: string;
  id: string;
  meta: string;
  onOpen: () => void;
  title: string;
};

export type OfficialActivityItem = {
  detail: string;
  id: string;
  label: string;
  onOpen?: () => void;
  title: string;
  tone?: "accent" | "info" | "neutral" | "warning";
};

function ActionControl({ action }: { action: OfficialHomeAction }) {
  const content = <><span>{action.eyebrow}</span><strong>{action.label}</strong><small>{action.detail}</small></>;
  if (action.href) return <Link className={styles.nextAction} data-primary-action="true" href={action.href}>{content}</Link>;
  return <button className={styles.nextAction} data-primary-action="true" type="button" onClick={action.onClick}>{content}</button>;
}

export function OfficialTeamIdentityBand({
  actions,
  context,
  name,
  object,
  role,
  status,
}: {
  actions?: ReactNode;
  context: string;
  name: string;
  object: ReactNode;
  role?: string;
  status?: string;
}) {
  return (
    <section className={styles.identityBand} data-official-identity-band="true">
      <div className={styles.identityCopy}>
        <span>Vestuario</span>
        <h1>{name}</h1>
        <p>{context}</p>
        {role || status ? <div className={styles.identityMeta}>{role ? <b>{role}</b> : null}{status ? <small>{status}</small> : null}</div> : null}
      </div>
      <div className={styles.objectStage}>{object}</div>
      {actions ? <div className={styles.identityActions}>{actions}</div> : null}
    </section>
  );
}

export function OfficialSeasonMetrics({ metrics }: { metrics: OfficialHomeMetric[] }) {
  return (
    <section className={styles.metrics} aria-label="Estado del equipo" data-official-season-metrics="true">
      {metrics.slice(0, 4).map((metric) => <div key={metric.label}><span>{metric.label}</span><strong>{metric.value}</strong></div>)}
    </section>
  );
}

export function OfficialUpcomingMatchesRail({
  emptyAction,
  matches,
}: {
  emptyAction?: ReactNode;
  matches: OfficialUpcomingMatch[];
}) {
  return (
    <section className={styles.band} data-official-upcoming-rail="true">
      <header><div><span>Agenda</span><h2>Próximos partidos</h2></div><small>{matches.length} programado{matches.length === 1 ? "" : "s"}</small></header>
      {matches.length ? (
        <div className={styles.rail}>
          {matches.map((match) => (
            <button className={styles.matchTile} key={match.id} type="button" onClick={match.onOpen}>
              <span>{match.date}</span>
              <strong>{match.title}</strong>
              <b>{match.context}</b>
              <small>{match.meta}</small>
            </button>
          ))}
        </div>
      ) : <div className={styles.empty}><div><strong>Sin partidos programados</strong><p>La agenda se llenará cuando exista el siguiente partido confirmado.</p></div>{emptyAction}</div>}
    </section>
  );
}

export function OfficialActivityRail({ items }: { items: OfficialActivityItem[] }) {
  return (
    <section className={styles.band} data-official-activity-rail="true">
      <header><div><span>Actividad</span><h2>Temporada</h2></div><small>{items.length} movimiento{items.length === 1 ? "" : "s"}</small></header>
      {items.length ? (
        <div className={styles.activityRail}>
          {items.map((item) => {
            const content = <><span data-tone={item.tone ?? "neutral"}>{item.label}</span><strong>{item.title}</strong><small>{item.detail}</small></>;
            return item.onOpen
              ? <button key={item.id} type="button" onClick={item.onOpen}>{content}</button>
              : <article key={item.id}>{content}</article>;
          })}
        </div>
      ) : <div className={styles.empty}><div><strong>Sin actividad reciente</strong><p>No mostramos eventos ficticios. Los resultados y avisos confirmados aparecerán aquí.</p></div></div>}
    </section>
  );
}

export function OfficialTeamAccess({ children, selector }: { children?: ReactNode; selector: ReactNode }) {
  return (
    <details className={styles.teamAccess} data-official-team-access="identity">
      <summary aria-label="Cambiar o administrar equipo">Equipo</summary>
      <div className={styles.teamAccessDrawer}>
        <div className={styles.teamSelectorSlot}>{selector}</div>
        {children}
      </div>
    </details>
  );
}

export function OfficialSecondaryActions({ children }: { children: ReactNode }) {
  return (
    <details className={styles.secondaryActions}>
      <summary aria-label="Abrir acciones secundarias">Más</summary>
      <div>{children}</div>
    </details>
  );
}

export function OfficialHomeGameDashboard({
  access,
  activity,
  identity,
  metrics,
  nextAction,
  object,
  secondaryActions,
  upcoming,
}: {
  access?: ReactNode;
  activity: OfficialActivityItem[];
  identity: { context: string; name: string; role?: string; status?: string };
  metrics: OfficialHomeMetric[];
  nextAction: OfficialHomeAction;
  object: ReactNode;
  secondaryActions?: ReactNode;
  upcoming: OfficialUpcomingMatch[];
}) {
  return (
    <div className={styles.dashboard} data-official-home-dashboard="v2.1">
      <OfficialTeamIdentityBand
        actions={access || secondaryActions ? <div className={styles.identityControlGroup} data-official-identity-controls="integrated">{access}{secondaryActions}</div> : undefined}
        context={identity.context}
        name={identity.name}
        object={object}
        role={identity.role}
        status={identity.status}
      />
      <div className={styles.actionRow}>
        <ActionControl action={nextAction} />
        <OfficialSeasonMetrics metrics={metrics} />
      </div>
      <OfficialUpcomingMatchesRail matches={upcoming} />
      <OfficialActivityRail items={activity} />
    </div>
  );
}
