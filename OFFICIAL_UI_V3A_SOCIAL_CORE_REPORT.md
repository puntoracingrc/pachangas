# Official UI V3A - Social Core

Estado: IN PROGRESS

## Checkpoint

- Base exacta: `f479a288e21916880694909e172323d2ed0e6551`.
- Rama: `codex/official-ui-v3a-social-core`.
- Wave 9C: no iniciada; no existe rama ni PR que pausar.
- Supabase: fuera de alcance. No se anadiran migraciones, RPC, RLS ni cambios de datos.
- Demo World V3.5: autoridad y snapshots preservados sin cambios.

## Alcance

Official UI V3A reduce la experiencia normal a cuatro destinos primarios:

1. Inicio.
2. Partidos.
3. Retos.
4. Mercado.

Perfil, carta, equipo, avisos y ajustes pasan a accesos de identidad. Las
capacidades avanzadas permanecen en el Control Center y solo se revelan tras
confirmar el rol canonico del servidor. No se autoriza mediante email en el
cliente.

## Auditoria inicial

- El contrato vigente publica seis destinos primarios y herramientas
  contextuales adicionales.
- El shell desktop y landscape renderiza esas herramientas como una segunda
  navegacion.
- Mercado mezcla descubrimiento social con Retos, Clubs y Arbitros.
- Mundo Demo publica por defecto catorce dominios tecnicos.
- El Control Center ya dispone de un shell separado y de acceso canonico por
  rol/capacidades.

## Gates de cierre

- Navegacion social consistente en desktop, portrait y landscape.
- Cero flash de capacidades avanzadas antes del readback canonico.
- Retos independiente y redireccion del deep link legado.
- Mercado reducido a Partidos, Jugadores y Equipos.
- Demo social por defecto y Demo completa solo desde administracion autorizada.
- Deep links, PWA, offline y rotacion preservados.
- Tests, typecheck, build, lint focalizado, `git diff --check` y QA visual.
- Merge, deployment y smoke productivo con el SHA exacto.

## Resultado final

Pendiente de implementacion y validacion.
