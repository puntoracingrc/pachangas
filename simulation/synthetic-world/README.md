# Pachangas IQ Synthetic World V1

Entorno local, persistente y reproducible para recorrer una temporada 2026-2027 con agentes sintéticos. No usa producción, no envía correo ni push reales y no crea usuarios externos.

## Límites de seguridad

- Solo acepta URLs loopback para aplicación y Supabase.
- Rechaza `VERCEL_ENV`, Supabase remoto y credenciales de servicios externos.
- El esquema `simulation` está revocado para `public`, `anon` y `authenticated`; solo lo utiliza `service_role` local.
- El dashboard devuelve 404 salvo con `PACHANGAS_SYNTHETIC_ADMIN=1` y nunca está disponible con `NODE_ENV=production`.
- Los identificadores, correos y nombres sintéticos están marcados como `SIM` y no contienen PII real.

## Preparación local

```bash
supabase start
PACHANGAS_BOOTSTRAP_DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:55322/postgres npm run db:bootstrap:fresh
psql -X -v ON_ERROR_STOP=1 "$PACHANGAS_SYNTHETIC_DB_URL" -f simulation/synthetic-world/sql/schema.sql
npm run test:synthetic-world:db
```

The product bootstrap never installs the `simulation` schema. That local-only schema is applied explicitly on the next line and remains inaccessible to `anon` and `authenticated`.

Variables mínimas, tomando como referencia [`.env.example`](./.env.example):

```dotenv
PACHANGAS_SYNTHETIC_WORLD=1
PACHANGAS_SYNTHETIC_ADMIN=1
NEXT_PUBLIC_APP_URL=http://127.0.0.1:3090
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:55321
PACHANGAS_SYNTHETIC_DB_URL=postgresql://postgres:postgres@127.0.0.1:55322/postgres
```

## Operaciones

```bash
npm run synthetic:inventory
npm run synthetic:core-social-v2
npm run synthetic:conduct-inventory
npm run synthetic:world -- create --seed 20260809 --name "Mundo de prueba"
npm run synthetic:world -- advance --world <uuid> --days 7 --snapshot 1
npm run synthetic:world -- season --seed 20260809
npm run synthetic:world -- clone --world <uuid> --seed 20260810
npm run synthetic:world -- reconcile-conduct --world <uuid>
npm run synthetic:world -- reconcile-ranking --world <uuid>
npm run synthetic:world -- sync-incidents --world <uuid>
npm run synthetic:world -- export --world <uuid>
npm run synthetic:ranking-funnel
npm run synthetic:network-v31
npm run synthetic:territory-readiness
```

Toda mutación persistente exige `operationId` y revisión esperada. Un replay devuelve el mismo recibo; una revisión obsoleta se rechaza. El reloj solo avanza y los snapshots no sustituyen el historial de eventos.

## Dashboard

```bash
PACHANGAS_SYNTHETIC_ADMIN=1 npm run dev -- --hostname 127.0.0.1 --port 3090
```

Abrir `http://127.0.0.1:3090/admin/simulation-world`. Incluye resumen, timeline, agentes, equipos, partidos, ranking, `Ranking funnel`, `Network Health`, conducta, cobertura e incidencias. `Ranking funnel` permite inspeccionar gates, distribuciones, provincias, un jugador concreto y la traza match-confidence de cada Reto. `Network Health` muestra la investigación V3.1, el grafo territorial, M0-M5 y el contrato TOPS V1 de readiness; M3 sigue siendo experimental y no activa ningún cambio de fórmula. Las tablas pesadas se cargan después del shell y la API responde con `Cache-Control: no-store`.

El piloto de lectura está en `http://127.0.0.1:3090/laboratorio-ranking-provincial`. Usa dos flags independientes: `provincial_rankings_enabled` (por defecto `true`) y `provincial_awards_enabled` (por defecto `false`). La UI pública nunca muestra señales antifraude y diferencia posición viva de premio de temporada.

Las auditorías V1.1/V3.1/TOPS V1 usan como fuente inmutable el mundo `3df9494d-3b8c-4447-96e8-d5244892af78` en revisión 313. Los comandos V1.1/V3.1 crean o reutilizan únicamente los clones A-E y M0-M5; TOPS V1 no guarda clones ni modifica el mundo. Generan [`../../RANKING_FUNNEL_V1_1_REPORT.md`](../../RANKING_FUNNEL_V1_1_REPORT.md), [`../../NETWORK_DIVERSITY_V3_1_REPORT.md`](../../NETWORK_DIVERSITY_V3_1_REPORT.md) y [`../../TERRITORY_AWARD_READINESS_V1_REPORT.md`](../../TERRITORY_AWARD_READINESS_V1_REPORT.md).

## Verificación

```bash
npm run test:synthetic-world
npm run synthetic:ranking-funnel
npm run synthetic:soak
npm run test:synthetic-world:dashboard-api
npm run typecheck
npm run build
```

Los flujos reales localizados y sus límites están en [`generated/product-inventory.md`](./generated/product-inventory.md). La auditoría específica de conducta está en [`generated/conduct-inventory.md`](./generated/conduct-inventory.md). El informe final vive en [`../../SYNTHETIC_WORLD_V1_REPORT.md`](../../SYNTHETIC_WORLD_V1_REPORT.md).
