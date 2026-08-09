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
psql -X -v ON_ERROR_STOP=1 "$PACHANGAS_SYNTHETIC_DB_URL" -f simulation/synthetic-world/sql/schema.sql
npm run test:synthetic-world:db
```

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
```

Toda mutación persistente exige `operationId` y revisión esperada. Un replay devuelve el mismo recibo; una revisión obsoleta se rechaza. El reloj solo avanza y los snapshots no sustituyen el historial de eventos.

## Dashboard

```bash
PACHANGAS_SYNTHETIC_ADMIN=1 npm run dev -- --hostname 127.0.0.1 --port 3090
```

Abrir `http://127.0.0.1:3090/admin/simulation-world`. Incluye resumen, timeline, agentes, equipos, partidos, ranking, `Ranking funnel`, `Network Health`, conducta, cobertura e incidencias. `Ranking funnel` permite inspeccionar gates, distribuciones, provincias, un jugador concreto y la traza match-confidence de cada Reto. `Network Health` muestra la investigación V3.1, el grafo territorial, M0-M5, tamaño de ecosistema y readiness; no activa ningún cambio de producto. Las tablas pesadas se cargan después del shell y la API responde con `Cache-Control: no-store`.

Las auditorías V1.1/V3.1 usan como fuente inmutable el mundo `3df9494d-3b8c-4447-96e8-d5244892af78` en revisión 313. Los comandos crean o reutilizan únicamente los clones A-E y M0-M5 y generan [`../../RANKING_FUNNEL_V1_1_REPORT.md`](../../RANKING_FUNNEL_V1_1_REPORT.md) y [`../../NETWORK_DIVERSITY_V3_1_REPORT.md`](../../NETWORK_DIVERSITY_V3_1_REPORT.md); nunca reescriben el mundo original.

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
