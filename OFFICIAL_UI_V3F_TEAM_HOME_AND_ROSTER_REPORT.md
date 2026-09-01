# Official UI V3F - Team Home and Roster

Fecha: 2026-09-02 (Europe/Madrid)

## Producto

V3F convierte `/equipo` en una superficie real y mantiene la navegación
principal de V3A en cuatro destinos: Inicio, Partidos, Retos y Mercado. Equipo
se abre desde el selector/contexto y se divide en:

- `/equipo`: escudo, nombre, modalidad, zona, miembros, próxima acción,
  resumen de plantilla y actividad social segura;
- `/equipo/plantilla`: admins y jugadores con avatar, nombre, posición, rol y
  estado reducido;
- `/equipo/invitaciones`: creación, compartir y revocación V2 solo para
  owner/admin.

La portada mantiene una acción principal y dos secundarias visibles. Crear el
primer partido entrega el flujo a V3B; Retos y Mercado continúan en V3C/V3D.
No aparecen Clubs, Ligas, Torneos, árbitros, Billing ni controles técnicos.

## Autoridad y privacidad

- El cliente consume `MyTeams`, `SocialTeamHome`, `SocialTeamRoster` y la lista
  reducida de invitaciones.
- El selector conserva el equipo elegido únicamente mientras siga autorizado.
- Ninguna fila expone email, teléfono, Auth UUID, hash, token persistido,
  revisión técnica o motivo operativo privado.
- El jugador ordinario es read-only; owner/admin reciben solo las acciones
  sociales que les corresponden.
- Realtime invalida y vuelve a consultar; el payload WAL nunca se aplica como
  autoridad.
- Caché local: snapshots canónicos de lectura por usuario/equipo. No hay cola
  offline de escrituras deportivas o sociales.

## Demo World

El recorrido `data-demo-social-first-time=v3f` contiene las 26 historias
solicitadas: perfil, tres pasos de creación, owner, equipo activo, código sin
acceso, invitación, perspectiva player, aceptación, replay, revocación, primer
partido V3B, varios equipos, V3C, V3D, offline y reset.

Contadores acreditados por contrato y UI:

- remote writes: `0`;
- external notifications: `0`;
- real entities: `0`;
- Stripe calls: `0`.

## QA local

- Matriz: `1440x900`, `1920x1080`, `390x844`, `360x800`, `667x375`,
  `740x360`, `844x390` y `932x430`.
- Demo y onboarding: 0 root overflow, controles cortados, imágenes rotas,
  overlays o errores de consola.
- Portrait y Mobile Game Landscape mantienen una sola navegación y permiten
  scroll vertical cuando la altura es limitada.
- Foco inicial dentro del diálogo, `aria-modal`, `aria-labelledby`, campos
  etiquetados, botones con nombre y cierre con Escape: PASS.
- Android físico, iPhone físico y PWA instalada física: `PENDING`.

Staging y producción: pendientes del release coordinado V3F.
