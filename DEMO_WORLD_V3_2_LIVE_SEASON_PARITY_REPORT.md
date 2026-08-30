# Demo World V3.2 Live Season Parity

## Contrato

- version: `3.2`
- seed: `pachangas-iq-synthetic-season-v1-2026-27`
- manifest hash: `9b3b503869f77b66a00f0e721e884616a026cf6a27edbb5e74f78d2057be85e7`
- transporte publico: `GET` exclusivamente
- remote writes: `0`
- snapshots historicos V2.1-V3.1: preservados

## Superficies

La tab `Temporada` se integra en la shell Demo existente y ofrece:

Resumen, Ligas, Torneos, Jornadas, Partidos, Clasificaciones, Cuadros,
Disciplina, Arbitros, Equipos, Clubs, Mercado, Retos, Organizacion,
Incidencias y Timeline.

El selector local conserva checkpoint, perspectiva y competicion. Auto-play
recorre snapshots publicados, permite pausa/salto y respeta
`prefers-reduced-motion`. El Control Center noindex muestra version, seed,
hashes, conteos, invariantes, fault injection, privacidad y cleanup, sin boton
de ejecucion remota.

## PWA

El Service Worker admite rutas versionadas `v3-2`, precachea el manifest y
cachea solo chunks publicos con hash. No cachea API privada, Auth, Supabase,
Stripe ni commands. Una escritura offline se rechaza y nunca se presenta como
confirmada.

Validacion local sobre build productivo:

- manifest `200`, `display: fullscreen` y fallback standalone;
- `/sw.js` activo y controlador, con `Cache-Control: no-store`;
- manifest, chunks y los nueve checkpoints V3.2 presentes en Cache Storage;
- recarga offline PASS;
- cambio local Pretemporada -> Postemporada y apertura de Cuadros offline PASS;
- auto-play avanza un checkpoint, pausa sin avanzar y queda deshabilitado con
  `prefers-reduced-motion: reduce`;
- composicion standalone simulada en 390x844: cero overflow e imagenes rotas.

Android, iPhone y PWA instalada en dispositivo fisico permanecen `PENDING`.

## Privacidad

Todos los JSON de `public/demo-world/v3-2` pasan el scan serializado:

- Auth UUID: 0
- emails: 0
- telefonos: 0
- evidence privada: 0
- secrets/tokens: 0
- Stripe IDs: 0
- URLs PostgreSQL/Supabase: 0

## QA visual

Matriz local sobre build productivo: `128/128 PASS`, combinando las dieciseis
vistas con 1440x900, 1920x1080, 390x844, 360x800, 667x375, 740x360,
844x390 y 932x430.

Resultado:

- root overflow: 0;
- controles mas anchos que viewport: 0;
- imagenes rotas: 0;
- `undefined`/`NaN` visibles: 0;
- warnings de hidratacion o errores de consola: 0;
- ultimo checkpoint accesible: PASS;
- rail, superficie central y panel de cambios con scroll interno: PASS;
- cruce Liga/Torneo/Jornada/Clasificacion/Cuadro/Partido/Organizacion: PASS;
- Control Center noindex en 1440x900, 390x844 y 844x390: PASS;
- PWA standalone simulada 390x844: PASS.

La misma matriz de alto valor se repetira en Preview exacta antes del merge.
