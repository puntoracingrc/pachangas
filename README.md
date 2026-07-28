# Pachanga IQ

App para organizar pachangas: asistencia, equipos equilibrados, campos, pagos, resultados, goles e historial.

## Desarrollo

```bash
npm install
npm run dev
```

## Build

```bash
npm run build
npm test
```

## Variables

```bash
NEXT_PUBLIC_SUPABASE_URL=https://TU_PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

La app usa Supabase con usuarios anonimos, RLS y Realtime. No uses ni subas la `service_role`.
