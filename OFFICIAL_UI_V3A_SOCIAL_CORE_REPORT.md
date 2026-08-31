# Official UI V3A - Social Core

Estado: LOCAL RELEASE CANDIDATE

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

## Resultado funcional

- La navegacion primaria es exactamente `Inicio / Partidos / Retos / Mercado`
  en desktop, portrait y Mobile Game Landscape.
- El escudo, nombre de equipo y avatar concentran el contexto de identidad. El
  menu de cuenta contiene perfil, carta, equipo, ajustes y cierre de sesion.
- `Administracion` y `Mundo Demo completo` solo aparecen despues de confirmar
  el rol canonico exacto `platform_owner` mediante el read model del servidor.
  El estado inicial es cerrado y no se utiliza el email como autorizacion.
- Los owners/admins de equipo conservan la gestion contextual. Un jugador no
  recibe controles de administracion de equipo.
- Partidos programados usan `Resumen / Jugadores / Equipos`; los finalizados
  usan `Resumen / Resultado / Estadisticas`. La administracion es una accion
  contextual, no una pestana permanente.
- Retos dispone de ruta propia `/retos`, con `Recibidos / Enviados / Historial /
  Buscar rival`. Los deep links antiguos de Retos en Mercado se redirigen.
- Mercado queda limitado a `Partidos / Jugadores / Equipos`, abre por Partidos
  y despliega filtros de forma progresiva.
- `/demo` abre la experiencia social sanitizada y de solo lectura. La Demo
  tecnica completa vive en `/admin/demo` y exige `platform_owner` canonico.
- El footer se oculta dentro de la experiencia autenticada, sin eliminar sus
  rutas legales ni el acceso desde Ajustes.

## Autoridad y seguridad

- No se han modificado migraciones, RPC, RLS, flags, datos ni configuracion de
  Supabase.
- No se han modificado Rating V2, Rewards, Conduct, disciplina, arbitros,
  calendarios, reservas, billing ni Stripe.
- La deteccion de plataforma es `no-store`, deriva de la sesion autenticada y
  falla cerrada. No existe allowlist de emails en el navegador.
- El cliente no fabrica permisos ni usa el payload Realtime como autoridad.
- Las rutas avanzadas existentes se preservan y solo se separan de la
  navegacion social normal.

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

## Validacion local

- `npm test`: PASS.
  - Build Next.js 16.3.3: PASS, 70 paginas generadas.
  - Node: 20/20.
  - TS/TSX: 695/695.
  - Total real: 715/715.
  - Fail / skipped / todo / cancelled: 0 / 0 / 0 / 0.
- Regresion focalizada de las superficies reconciliadas: 107/107 PASS.
- Suite contractual V3A: 6/6 PASS.
- `npm run typecheck`: PASS.
- `npm run lint`: PASS con 0 errores y 3 warnings preexistentes en
  `app/page.tsx`.
- `git diff --check`: PASS.

## QA visual local

| Superficie | 1440x900 | 390x844 | 844x390 | Resultado |
| --- | --- | --- | --- | --- |
| Inicio | PASS | PASS | PASS | Navegacion y shell estables |
| Partidos | PASS | PASS | PASS | Submenus por estado correctos |
| Retos | PASS | PASS | PASS | Ruta independiente y sin overflow |
| Mercado | PASS | PASS | PASS | Tres pestanas y Partidos por defecto |
| Demo social | PASS | PASS | PASS | Sin dominios tecnicos en primer nivel |
| Demo completa | Protegida | Protegida | Protegida | Fail-closed sin platform_owner |

- Ancho del documento igual al viewport en 390 y 844 px; los carriles
  horizontales internos conservan su desplazamiento intencional.
- Cero errores de consola de producto, cero imagenes rotas y cero overflow del
  documento en las rutas inspeccionadas.
- Manifest y Service Worker responden 200 con MIME correcto.
- Emulacion PWA `standalone` en 390x844: PASS, shell de cuatro destinos y ancho
  390/390. El registro real del worker se comprobara en Vercel porque Next dev
  local no lo activa.

## Release

- Commit de implementacion:
  `dc8b1fca58e9c4f07a939a19a702e16c88cf363c`.
- Diff funcional: 42 rutas de codigo y tests. El informe es la unica ruta
  documental adicional frente a la base.
- PR: #241, draft durante la validacion de Preview.
- Preview validada:
  `https://pachangas-git-codex-offic-4637a7-persianas-almar-web-s-projects.vercel.app`.
  - Deployment: `dpl_8zW4KLKN3VYeVTm6a2Jvnyjpc6CZ`.
  - HEAD auditado: `3e0b043e894e7def8a62fbf380bff1ce44a9bcc4`.
  - Estado Vercel: READY.
  - Desktop 1440x900, portrait 390x844 y landscape 844x390: PASS.
  - Consola: 0 errores y 0 warnings en las superficies de producto.
  - Imagenes rotas / overflow del documento: 0 / 0.
  - Manifest: 200 `application/manifest+json`.
  - Service Worker: 200, `activated` y controlando la pagina.
  - `/admin/demo` sin sesion de Pachangas: fail-closed, sin Demo completa ni
    dominios tecnicos.
- Merge a `main`: pendiente.
- Deployment productivo: pendiente.
- Smoke en `pachangasiq.com`: pendiente.

Wave 9C no se ha iniciado. La fase no se considerara cerrada hasta completar
Preview, merge, deployment, smoke productivo y limpieza segura del worktree.
