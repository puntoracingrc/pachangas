"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

import { RATING_COMPARISON_OPTIONS, type RatingComparison } from "./rating-system-v2";

type CanonicalCommit = {
  confirmedRevision?: number | string;
  payload?: unknown;
  payload_revision?: number | string;
  ratingsEnabled?: boolean;
};

type GlobalGuest = {
  id: string;
  name: string;
  observationCount: number;
  provisionalLevel: number | null;
};

type ExternalTeam = {
  calibratedLevel: number | null;
  id: string;
  name: string;
  zone: string | null;
};

type RegisteredOpponent = {
  externallyCalibratedLevel: number | null;
  groupId: string;
  name: string;
  teamCode: string;
};

type OwnResponse = {
  comparison: RatingComparison;
  externalTeamId?: string | null;
  guestId?: string | null;
  targetKind: "external_team" | "guest" | "registered_group";
};

type GlobalRatingContext = {
  externalTeams: ExternalTeam[];
  guests: GlobalGuest[];
  note: string;
  ownResponses: OwnResponse[];
  referenceLevel: number | null;
  registeredOpponent: RegisteredOpponent | null;
};

type Props = {
  client: SupabaseClient;
  clientMetadata: () => Record<string, unknown>;
  expectedRevision: number | null;
  groupId: string;
  matchId: string;
  onCommit: (commit: CanonicalCommit) => void;
};

function responseKey(kind: OwnResponse["targetKind"], id: string) {
  return `${kind}:${id}`;
}

export function GlobalRatingPanel({ client, clientMetadata, expectedRevision, groupId, matchId, onCommit }: Props) {
  const [context, setContext] = useState<GlobalRatingContext | null>(null);
  const [loading, setLoading] = useState(true);
  const [busyKey, setBusyKey] = useState("");
  const [message, setMessage] = useState("");
  const [rivalName, setRivalName] = useState("");
  const [rivalZone, setRivalZone] = useState("");
  const [registeredTeamCode, setRegisteredTeamCode] = useState("");

  const loadContext = useCallback(async () => {
    const result = await client.rpc("get_pachanga_global_rating_context_v2", {
      target_group_id: groupId,
      target_match_id: matchId,
    });
    setLoading(false);
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    setContext(result.data as GlobalRatingContext);
  }, [client, groupId, matchId]);

  useEffect(() => {
    let cancelled = false;
    void Promise.resolve(client.rpc("get_pachanga_global_rating_context_v2", {
      target_group_id: groupId,
      target_match_id: matchId,
    })).then((result) => {
      if (cancelled) return;
      setLoading(false);
      if (result.error) {
        setMessage(result.error.message);
        return;
      }
      setContext(result.data as GlobalRatingContext);
    });
    return () => {
      cancelled = true;
    };
  }, [client, groupId, matchId]);

  const ownResponses = useMemo(() => new Map(
    (context?.ownResponses ?? []).flatMap((response) => {
      const id = response.guestId ?? response.externalTeamId;
      return id ? [[responseKey(response.targetKind, id), response.comparison] as const] : [];
    }),
  ), [context?.ownResponses]);

  async function createExternalTeam() {
    const name = rivalName.trim();
    if (!name || expectedRevision === null || busyKey) return;
    setBusyKey("external:new");
    setMessage("");
    const result = await client.rpc("ensure_pachanga_external_team_authoritative_v2", {
      client_metadata: clientMetadata(),
      display_name: name,
      expected_revision: expectedRevision,
      operation_id: crypto.randomUUID(),
      target_group_id: groupId,
      target_match_id: matchId,
      zone: rivalZone.trim() || null,
    });
    setBusyKey("");
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    onCommit(result.data as CanonicalCommit);
    setRivalName("");
    setRivalZone("");
    setMessage("Rival preparado para valoración global.");
    await loadContext();
  }

  async function linkRegisteredOpponent() {
    const teamCode = registeredTeamCode.trim();
    if (!teamCode || expectedRevision === null || busyKey) return;
    setBusyKey("registered:link");
    setMessage("");
    const result = await client.rpc("link_pachanga_registered_opponent_authoritative_v2", {
      client_metadata: clientMetadata(),
      expected_revision: expectedRevision,
      operation_id: crypto.randomUUID(),
      opponent_team_code: teamCode,
      target_group_id: groupId,
      target_match_id: matchId,
    });
    setBusyKey("");
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    onCommit(result.data as CanonicalCommit);
    setRegisteredTeamCode("");
    setMessage("Grupo rival enlazado a este partido.");
    await loadContext();
  }

  async function saveComparison(kind: "guest" | "external_team" | "registered_group", targetId: string, comparison: RatingComparison) {
    if (expectedRevision === null || busyKey) return;
    const key = responseKey(kind, targetId);
    setBusyKey(key);
    setMessage("");
    const result = await client.rpc("record_pachanga_global_rating_authoritative_v2", {
      client_metadata: clientMetadata(),
      comparison,
      expected_revision: expectedRevision,
      operation_id: crypto.randomUUID(),
      rated_group_id: kind === "registered_group" ? targetId : null,
      target_external_team_id: kind === "external_team" ? targetId : null,
      target_group_id: groupId,
      target_guest_id: kind === "guest" ? targetId : null,
      target_kind: kind,
      target_match_id: matchId,
    });
    setBusyKey("");
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    onCommit(result.data as CanonicalCommit);
    setMessage("Valoración guardada. Las respuestas de los admins se combinan en una sola observación oficial.");
    await loadContext();
  }

  async function issueGuestLink(guest: GlobalGuest) {
    if (expectedRevision === null || busyKey) return;
    const key = `token:${guest.id}`;
    setBusyKey(key);
    setMessage("");
    const result = await client.rpc("issue_pachanga_guest_rating_token_authoritative_v2", {
      client_metadata: clientMetadata(),
      expected_revision: expectedRevision,
      expires_in_minutes: 1440,
      operation_id: crypto.randomUUID(),
      target_group_id: groupId,
      target_guest_id: guest.id,
      target_match_id: matchId,
    });
    setBusyKey("");
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    const commit = result.data as CanonicalCommit & { token?: string };
    onCommit(commit);
    if (!commit.token) {
      setMessage("El enlace ya se había generado. Crea uno nuevo para sustituirlo.");
      return;
    }
    const url = `${window.location.origin}/valorar-equipo?t=${encodeURIComponent(commit.token)}`;
    try {
      await navigator.clipboard.writeText(url);
      setMessage(`Enlace de un solo uso copiado para ${guest.name}. Caduca en 24 horas.`);
    } catch {
      window.prompt("Copia el enlace seguro", url);
      setMessage(`Enlace preparado para ${guest.name}. Caduca en 24 horas.`);
    }
  }

  function comparisonButtons(kind: "guest" | "external_team" | "registered_group", id: string) {
    const key = responseKey(kind, id);
    const selected = ownResponses.get(key);
    return (
      <div className="global-rating-options" aria-label="Comparación global">
        {RATING_COMPARISON_OPTIONS.map((option) => (
          <button
            aria-pressed={selected === option.id}
            className={selected === option.id ? "selected" : ""}
            disabled={Boolean(busyKey) || expectedRevision === null}
            key={option.id}
            onClick={() => void saveComparison(kind, id, option.id)}
            type="button"
          >
            {option.label}
          </button>
        ))}
      </div>
    );
  }

  return (
    <section className="global-rating-panel" aria-label="Valoraciones globales del partido">
      <header>
        <div>
          <span>Valoraciones globales</span>
          <strong>Referencia: vuestra alineación ({context?.referenceLevel === null || context?.referenceLevel === undefined ? "pendiente" : Math.round(context.referenceLevel)})</strong>
        </div>
        <small>Las respuestas de varios admins forman una única observación oficial por objetivo.</small>
      </header>

      {loading ? <p>Cargando objetivos del partido...</p> : null}
      {!loading && context ? (
        <div className="global-rating-groups">
          <section>
            <div className="global-rating-section-title">
              <strong>Rival externo</strong>
              <small>Valoración del equipo completo, nunca de sus jugadores.</small>
            </div>
            <div className="external-team-create-row">
              <input aria-label="Nombre del rival" placeholder="Nombre del rival" value={rivalName} onChange={(event) => setRivalName(event.target.value)} />
              <input aria-label="Zona del rival" placeholder="Zona opcional" value={rivalZone} onChange={(event) => setRivalZone(event.target.value)} />
              <button disabled={!rivalName.trim() || Boolean(busyKey) || expectedRevision === null} onClick={() => void createExternalTeam()} type="button">
                Añadir rival
              </button>
            </div>
            <div className="external-team-create-row registered-opponent-row">
              <input
                aria-label="Código del grupo rival registrado"
                placeholder="Código de grupo rival"
                value={registeredTeamCode}
                onChange={(event) => setRegisteredTeamCode(event.target.value.toUpperCase())}
              />
              <button
                disabled={!registeredTeamCode.trim() || Boolean(busyKey) || expectedRevision === null}
                onClick={() => void linkRegisteredOpponent()}
                type="button"
              >
                Enlazar grupo rival
              </button>
            </div>
            {context.registeredOpponent ? (
              <article className="global-rating-target" key={context.registeredOpponent.groupId}>
                <div>
                  <strong>{context.registeredOpponent.name}</strong>
                  <small>
                    Grupo registrado · {context.registeredOpponent.teamCode}
                    {context.registeredOpponent.externallyCalibratedLevel === null
                      ? ""
                      : ` · nivel externo ${Math.round(context.registeredOpponent.externallyCalibratedLevel)}`}
                  </small>
                </div>
                {comparisonButtons("registered_group", context.registeredOpponent.groupId)}
              </article>
            ) : null}
            {context.externalTeams.map((team) => (
              <article className="global-rating-target" key={team.id}>
                <div>
                  <strong>{team.name}</strong>
                  <small>{team.zone || "Sin zona"}{team.calibratedLevel === null ? "" : ` · nivel externo ${Math.round(team.calibratedLevel)}`}</small>
                </div>
                {comparisonButtons("external_team", team.id)}
              </article>
            ))}
          </section>

          {context.guests.length > 0 ? (
            <section>
              <div className="global-rating-section-title">
                <strong>Invitados</strong>
                <small>Comparación global de cada invitado con vuestra alineación.</small>
              </div>
              {context.guests.map((guest) => (
                <article className="global-rating-target guest-target" key={guest.id}>
                  <div>
                    <strong>{guest.name}</strong>
                    <small>{guest.observationCount} observación{guest.observationCount === 1 ? "" : "es"}{guest.provisionalLevel === null ? "" : ` · provisional ${Math.round(guest.provisionalLevel)}`}</small>
                  </div>
                  {comparisonButtons("guest", guest.id)}
                  <button className="guest-rating-link-button" disabled={Boolean(busyKey) || expectedRevision === null} onClick={() => void issueGuestLink(guest)} type="button">
                    {busyKey === `token:${guest.id}` ? "Creando..." : "Copiar enlace para valorar al equipo"}
                  </button>
                </article>
              ))}
            </section>
          ) : null}
        </div>
      ) : null}
      {message ? <p className="global-rating-message" role="status">{message}</p> : null}
    </section>
  );
}
