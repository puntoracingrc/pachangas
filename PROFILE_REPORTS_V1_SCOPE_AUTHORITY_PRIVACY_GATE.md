# Profile Reports V1: Scope, Authority and Privacy Gate

## 1. Resumen ejecutivo

Pachangas IQ no dispone hoy de un canal genérico, persistente y autoritativo
para denunciar contenido o identidad publicados en perfiles. El formulario
`/reportar` existente pertenece a Conduct: exige una relación deportiva válida
y describe comportamiento ocurrido en un contexto deportivo. El reporte de una
competición pública es otro dominio independiente. Ninguno cubre de extremo a
extremo un avatar, nombre, bio, logo, descripción, suplantación o dato personal
publicado en un perfil.

El hueco de producto está confirmado. La arquitectura seleccionada es
`GENERALIZED_MODERATION_AUTHORITY`: un único agregado privado de casos de
moderación, compatible con Conduct mediante adaptadores, con intake y snapshot
específicos por dominio. No se crea una segunda autoridad de casos.

Sin embargo, la activación y la implementación permanecen bloqueadas. Faltan
decisiones que Codex no puede aprobar: política de seguridad de menores, ruta y
cobertura operativa de urgencias, responsable y capacidad de moderación,
retención, base jurídica, identidad/contacto legal y clasificación DSA. Este
gate fija el contrato técnico recomendado y documenta esas decisiones sin
suponer aprobación.

## 2. Estado del gate

```text
PROFILE REPORTS V1 GATE: BLOCKED BY PRODUCT OR LEGAL DECISION
```
Consecuencias:

- Profile Reports V1 no se implementa ni se activa.
- No existe un primer lote ejecutable.
- El issue #178 permanece abierto.
- Conduct, Competition Discipline, Team Operational State, Rating, rankings,
  rewards y billing permanecen intactos.
- Todos los flags futuros nacen conceptualmente en `OFF` y no se crean aquí.

Stop gate obligatorio:

```text
PROFILE REPORTS INTAKE MUST REMAIN OFF UNTIL MINOR-SAFETY POLICY IS APPROVED
```

## 3. SHA base

- Repositorio: `puntoracingrc/pachangas`.
- Rama de documentación: `codex/profile-reports-v1-definition`.
- Base auditada: `0dce1c2c6b7a891ba3ab0d3e65c0146a04e3b035`.
- `origin/main` coincidía con la base esperada al iniciar el gate.
- Última migración local y remota conocida: `20260904184204_r4b_interactive_schedule_capacity_v1`.
- Ledger revalidado: 237 migraciones locales y 237 remotas.

## 4. Issue #178

El issue [#178](https://github.com/puntoracingrc/pachangas/issues/178)
continúa abierto, sin evidencia posterior que invalide su contrato histórico:
Profile Reports no existe como flujo persistente y debe definir autoridad,
RLS, moderación, apelación y privacidad antes de activarse.

Este documento referencia el issue; no lo resuelve ni lo cierra. Tampoco edita
su cuerpo histórico.

## 5. Fuentes revisadas

### Producto y repositorio

- Informes de Social Player Profile, creación de Team, Official UI V3E/V3F,
  Player Profile/Card, Mercado, identidad pública de Team y consentimiento.
- Informes de Club Foundation, Clubs & Referees Beta, Referee Platform,
  marketplace arbitral y Referee Assignments.
- `CONDUCT_REPORTS_NO_SHOW_PROPOSAL.md`,
  `CONDUCT_REPORTS_NO_SHOW_V1_REPORT.md` y
  `CONDUCT_TRIAGE_V1_1_REPORT.md`.
- Informes de Platform Control Center, Production Feature Activation, Team
  Operational State, Social Restrictions y Competition Discipline.
- Contratos Social Core, Official UI V3H/V3I y sus regresiones.
- Rutas `/reportar`, `/perfil/conducta`, `/admin/conduct`, `/perfil`,
  `/mercado`, `/clubes/[slug]`, `/arbitros/[slug]`, `/campos/[slug]` y
  `/competiciones/[competition]`.
- Migraciones finales de Conduct, Triage, Social Profile, Club, Referee, Team
  Operational, Platform Control Center, Competition Discipline,
  notificaciones e invalidaciones.
- `app/legal-data.tsx`, client policy y PWA write bridge.

### Fuentes oficiales

- [Digital Services Act, Reglamento (UE) 2022/2065](https://eur-lex.europa.eu/eli/reg/2022/2065/oj).
- [Mecanismo notice-and-action de la Comisión Europea](https://digital-strategy.ec.europa.eu/en/policies/dsa-notice-and-action-mechanism).
- [RGPD, Reglamento (UE) 2016/679](https://eur-lex.europa.eu/legal-content/ES/TXT/?uri=CELEX:32016R0679).
- [LOPDGDD, texto consolidado del BOE](https://boe.es/buscar/act.php?id=BOE-A-2018-16673).
- [Protección de datos desde el diseño, AEPD](https://www.aepd.es/derechos-y-deberes/cumple-tus-deberes/medidas-de-cumplimiento/proteccion-de-datos-desde-el-diseno).
- [Guía AEPD de gestión de riesgos y evaluación de impacto](https://www.aepd.es/guias/gestion-riesgo-y-evaluacion-impacto-en-tratamientos-datos-personales.pdf).
- [Guidelines 4/2019 on Article 25, EDPB](https://www.edpb.europa.eu/documents/guideline/guidelines-42019-on-article-25-data-protection-by-design-and-by-default_en).
- [Coordinador de Servicios Digitales en España, CNMC](https://www.cnmc.es/sectores-que-regulamos/servicios-digitales-dsa/reclamaciones).

Este gate es un diseño técnico y de producto, no un dictamen jurídico.

## 6. Readback productivo

Lectura agregada y sin contenido sensible realizada el 4 de septiembre de 2026
a las 21:58 UTC sobre el proyecto Pachangas IQ:

| Comprobación | Resultado |
| --- | --- |
| Proyecto | `ACTIVE_HEALTHY`, región UE, PostgreSQL 17.6 |
| Ledger | 237 local / 237 remoto |
| Última migración | `20260904184204_r4b_interactive_schedule_capacity_v1` |
| Objeto genérico Profile Reports | 0 tablas y 0 rutinas localizadas |
| Conduct reports | 0 |
| Moderation cases | 0 |
| Warnings | 0 |
| Social restrictions | 0 |
| Conduct appeals | 0 |
| Competition reports | 0 |
| Conduct subject states | 0 |
| Social profiles | 0 |
| Player Market listings | 0 activas / 1 inactiva |
| Clubs | 4, públicos y archivados |
| Referee profiles | 2 archivados; 1 público no listado y 1 privado no listado |
| Challengeable Teams | 2 habilitados / 1 deshabilitado |
| Mandatory notifications | 17 |
| Realtime | Invalidadores de Conduct, Social, Club, Competition, Referee, Team y avisos presentes |

No se leyeron textos, identidades, correos, UUID de personas, notas, evidencia,
direcciones, IP ni agentes de usuario. No se escribió en producción.

## 7. Estado actual de Conduct

| Capacidad | Estado | Evidencia y límite |
| --- | --- | --- |
| Intake contextual | Implementado y `ON` | `submit_pachanga_conduct_report_v1`; exige contexto y relación deportiva válidos. |
| Attendance reliability | Implementado y `ON` | Dominio de asistencia, cancelación y no-show; no equivale a contenido de perfil. |
| Case authority | Implementada para persona/jugador | `private.pachanga_moderation_cases`; sujeto y categorías están tipados para Conduct/Attendance. |
| Evidencia | Implementada para Conduct | Contexto deportivo y snapshots propios de ese dominio. |
| Triage | Shadow `ON`, authority `OFF` | No autoriza decisiones automáticas. |
| Warnings/appeals | Implementados para Conduct | Aviso o restricción social; no son acciones sobre contenido publicado. |
| Social Restrictions | Implementadas pero `OFF` | No se activan ni reutilizan desde Profile Reports. |
| Privacidad social | Implementada | El target y admins ordinarios no reciben identidad del informante. |
| Profile/content report | Ausente | Conduct no admite organizaciones ni snapshot de campo/revisión de perfil. |

Extender directamente Conduct falsificaría relación deportiva, convertiría
contenido en comportamiento y mezclaría retirada de publicación con sanciones
sociales. El motor de casos sí aporta una base útil, pero necesita una
generalización compatible, no un nuevo valor improvisado en su intake actual.

Flags productivos revalidados:

```text
Conduct report intake: ON
Attendance: ON
Social Restrictions: OFF
Conduct Triage authority: OFF
Conduct Triage shadow: ON
```

## 8. Estado actual de perfiles

Pachangas ya tiene varias autoridades de publicación, revisión y visibilidad,
pero no una autoridad transversal de reporte:

- Social Player Profile mantiene perfil propio versionado y snapshots; su
  lectura directa es del propietario, mientras algunos campos se proyectan en
  contextos sociales autorizados.
- Player Market publica un listing opt-in visible para usuarios autenticados.
  Es una proyección de mercado, no una autoridad de moderación.
- Club y Referee tienen revisión, secuencia, estados de publicación,
  consentimiento y read models públicos.
- Team expone identidad, escudo y perfil retable mediante varias revisiones y
  proyecciones canónicas.
- Competition tiene su propio canal de reporte persistente.
- Venue publica contenido y ubicación, pero carece de un canal de reporte.
- No existe un perfil público canónico e indexable de jugador independiente de
  Mercado/Team en el main auditado.

## 9. Inventario de targets

Las dos tablas siguientes forman una única matriz, unida por `ID`.

### Autoridad y datos

| ID | Entidad canónica | Propietario | Tabla/autoridad | Revisión | Read model público | Campos públicos principales | Campos privados excluidos |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T1 | Social Player Profile | Usuario | `pachanga_social_player_profiles_v1` | Sí, revisión y secuencia | No hay URL pública autónoma; proyecciones contextuales | Nombre visible, avatar ref, posiciones, modalidad, zona general, disponibilidad, bio | Usuario interno, snapshots privados, operación, datos de cuenta |
| T2 | Player public profile | Usuario | No localizado como entidad pública autónoma | No aplicable | Ausente | Ausente | Todo el perfil privado universal |
| T3 | Player Card | Usuario + datos deportivos | Carta/read models canónicos | Sí en fuentes deportivas/cosméticas | Contextual en Team, partido o ranking | Nombre, avatar, posición, GRL/facetas autorizadas, cosméticos | Teléfono, nacimiento completo, lesión médica, votos, identidades de evaluadores |
| T4 | Player Market listing | Usuario | `pachanga_market_profiles` + command/sync V2 | Revisión de grupo en command actual; no historial autónomo completo del listing | Mercado autenticado | Nombre, avatar, bio, posición, media derivada, modalidades, zona general, disponibilidad, estadísticas | Contacto, coordenadas precisas, datos de cuenta, evidencia Rating |
| T5 | Referee public profile | Árbitro | `pachanga_referee_profiles` y revisiones | Sí | `/arbitros/[slug]` | Nombre, avatar, bio, experiencia, modalidades, áreas generales, disponibilidad pública, tarifa pública, estado | Identidad de cuenta, disponibilidad privada, notas, operaciones |
| T6 | Referee marketplace listing | Árbitro | Proyección de T5 | Misma revisión canónica de T5 | Mercado de árbitros | Subconjunto público de T5 | Igual que T5 |
| T7 | Club public profile | Club/owner autorizado | `pachanga_clubs` y revisiones/consent | Sí | `/clubes/[slug]` | Nombre, logo, descripción, tipo, zona general, equipos visibles, verified/partner | Owner, membresías, placeId y ubicación precisa, operaciones |
| T8 | Team public identity/profile | Team/owner/admin autorizado | Grupo + perfil retable + read models | Sí, según agregado | Mercado/retos y contextos públicos | Nombre, zona general, nivel, modalidades, disponibilidad, compatibilidad | Código privado, miembros/contactos, coordenadas, operaciones |
| T9 | Team shield/name/description | Team | identidad/escudo/cosméticos versionados | Sí | Embebido en T8 y superficies Team | Nombre, escudo, descripción pública cuando exista | Configuración privada, receipts, ownership |
| T10 | Public Competition profile | Organizador | Competition authority + `private.pachanga_competition_reports` | Sí | `/competiciones/[competition]` | Perfil y contenido de competición publicado | Configuración, grants, operaciones privadas |
| T11 | Public organizer profile | Organizador | No existe perfil autónomo; Club aparece como organizador | No autónoma | Embebido en T7/T10 | Nombre/Club de organización | Entitlements, billing, identidad privada |
| T12 | Public Venue profile | Club/gestor autorizado | Venue authority/read model | Sí | `/campos/[slug]` | Nombre, descripción, municipio, dirección pública según precisión, pistas, servicios, tarifas | Coordenadas privadas, disponibilidad y operaciones internas |
| T13 | Open/public match listing | Team/admin | Match/public-market authority | Sí, revisión de partido | Mercado/partido público | Fecha, modalidad, campo permitido, plazas, Team | Alineación privada, teléfonos, pagos, operaciones |

### Publicación, riesgo y decisión V1

| ID | Edición | Moderación actual | Consentimiento | Visibilidad/URL/indexación | Unpublish/histórico | Imagen | Ubicación | Menores | Canal actual | Profile Reports V1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1 | Propietario | Ninguna de contenido | Opt-in social | Sin URL autónoma; no indexable | Pausa/proyección; snapshot sí | Avatar | General | Sí | No | Solo cuando un campo esté publicado mediante T4; no target autónomo V1 |
| T2 | No aplicable | Ausente | Ausente | Ausente | Ausente | Posible | No | Sí | No | Fuera: entidad pública no existe |
| T3 | Datos derivados; cosméticos por propietario | Ninguna de contenido | Contextual | No indexable como perfil autónomo | Historial deportivo sí; no unpublish de carta | Avatar/cosméticos | No | Sí | No | Fuera como carta; reportar el campo publicado subyacente, nunca Rating |
| T4 | Propietario | Puede pausar listing; sin decisión moderadora | Opt-in Mercado | Autenticado, sin indexación pública confirmada | Unlist sí; historial autónomo insuficiente | Avatar | General | Sí | No | Incluido inicialmente, condicionado a target revision canónica |
| T5 | Árbitro; plataforma gestiona estado | Plataforma puede suspender/restaurar | Consent fingerprint | URL pública; indexable si public/active | Unlist/archive; revisiones sí | Avatar | General | Posible | No | Incluido |
| T6 | Mediante T5 | Igual que T5 | Igual que T5 | Marketplace; no URL distinta | Unlist mediante T5 | Avatar | General | Posible | No | Incluido como superficie de T5, sin duplicar target |
| T7 | Owner/admin; plataforma gestiona estado | Plataforma puede suspender/rechazar/archivar | Consent fingerprint invalidado al editar | URL pública; indexable si public/active | Ocultar/archive; revisiones sí | Logo | General | Posible | No | Incluido |
| T8 | Owner/admin | Team Operational separado; no modera contenido | Opt-in retable/público | Mercado/retos; indexación autónoma no confirmada | Disable/unlist; historial parcial | Escudo | General | Sí | No | Incluido para campos públicos allowlisted |
| T9 | Owner/admin | Ninguna acción de contenido específica | Publicación Team | Embebido; no URL distinta | Revisión/restauración según agregado | Escudo | No | Sí | No | Incluido como campo de T8, sin caso duplicado |
| T10 | Organizador | Reporte y moderación propios | Publicación Competition | URL pública indexable | Despublicar/estado; revisión sí | Assets de competición | General | Posible | Sí | Excluido: usar Competition Reports existente |
| T11 | Mediante Club/Competition | Según entidad subyacente | Según entidad | Sin URL autónoma | Según T7/T10 | Logo Club | General | Posible | Indirecto | Excluido: reportar T7 o T10, no entidad inventada |
| T12 | Gestor autorizado | Estado operativo; sin report intake | Publicación Venue | URL pública indexable | Puede ocultarse; revisión sí | Posible | Puede ser precisa | Sí | No | Diferido: requiere política específica de ubicación/gestor |
| T13 | Admin de partido | Autoridad transaccional, no moderación de perfil | Publicación de partido | URL/listing; indexación limitada | Cerrar/retirar según partido; historial sí | Foto de partido posible | Campo | Sí | Conduct solo tras contexto válido | Excluido: listing/transacción, no perfil; decisión futura separada |

Allowlist V1 recomendada, sujeta a desbloqueo: `PLAYER_MARKET_PROFILE`,
`REFEREE_PROFILE`, `CLUB_PROFILE` y `TEAM_PUBLIC_PROFILE`. Las superficies que
son proyecciones de la misma entidad no crean targets ni reportes duplicados.

## 10. Separación de dominios

| Señal del usuario | Dominio correcto | Relación exigida | Autoridad | Resultado permitido |
| --- | --- | --- | --- | --- |
| Conducta en partido/reto/guest finalizado | `CONDUCT REPORT CONTEXTUAL` | Deportiva verificable | Conduct | Caso Conduct, warning/restricción solo por decisión explícita |
| Nombre, avatar, bio, logo, descripción o identidad publicada | `PROFILE OR CONTENT REPORT` | Contenido públicamente visible; no partido | Intake Profile + autoridad común generalizada | Decisión y acción sobre contenido/publicación |
| Tarjeta, expulsión, elegibilidad o sanción deportiva | `COMPETITION DISCIPLINE` | Competición/partido oficial | Competition Discipline | Decisión deportiva y apelación deportiva |
| Lifecycle, limitación operativa o ownership de Team | `TEAM OPERATIONAL STATE` | Rol/autoridad de Team | Team Operational | Estado operativo y apelación de Team |
| Contenido presuntamente ilícito | `ILLEGAL CONTENT NOTICE` | Localización exacta del contenido | Canal jurídico separado, aún no aprobado | Acuse, decisión, motivos y recurso si aplica |
| Acceso, rectificación, supresión, privacidad o cuenta | `SUPPORT OR PRIVACY REQUEST` | Titularidad o representación | Soporte/privacidad | Trámite de derechos o soporte; no caso Conduct automático |
| Perfil de competición pública | Competition Report | Contenido de competición | Competition Reports actual | Flujo existente; no Profile Reports |

Bloquear, silenciar, abandonar un Team, reportar contenido y pedir soporte son
acciones distintas. Ninguna debe crear otra silenciosamente.

## 11. Hueco exacto

Faltan conjuntamente:

1. Intake genérico para contenido de perfil sin relación deportiva.
2. Resolución server-side de target, superficie, revisión y campo.
3. Snapshot objetivo del contenido público denunciado.
4. Enlace a una autoridad de caso capaz de representar persona, Team, Club y
   contenido sin falsear Conduct.
5. Decisiones y acciones explícitas sobre publicación/campo.
6. Read models separados para informante y target.
7. Apelación/reclamación vinculada a la decisión de contenido.
8. RLS/RBAC, deduplicación, rate limits y auditoría específicos.
9. Retención, urgencias, menores y operación aprobadas.
10. Entry points contextuales en perfiles públicos.

La existencia de `/reportar` no cubre ese hueco.

## 12. Arquitecturas evaluadas

| Opción | Resultado | Evaluación |
| --- | --- | --- |
| Extender directamente Conduct | Rechazada | Conduct exige relación deportiva, target persona y categorías/lifecycle de comportamiento; mezclaría contenido con sanción social. |
| Intake Profile específico hacia case engine compartido | Parcialmente válida | Es la forma correcta de intake, pero el case engine actual no representa Club/Team/content sin generalización. |
| Autoridad de moderación genérica con adaptadores | Seleccionada | Conserva un único agregado de casos y compatibilidad Conduct; añade adaptadores de intake/evidencia/acciones por dominio. |
| Sistema completamente paralelo | Rechazada | Duplicaría casos, operadores, auditoría, apelaciones y notificaciones sin justificación. |

## 13. Arquitectura seleccionada

```text
GENERALIZED_MODERATION_AUTHORITY
```

Diseño futuro:

```text
Profile intake específico
        |
        v
Target resolver + snapshot de revisión pública
        |
        v
Autoridad privada común de casos de moderación
        |
        +-- Adaptador Conduct existente
        +-- Adaptador Profile/Content
        +-- Acciones de contenido tipadas por target
        |
        v
Read models mínimos + notificaciones + invalidación
```

La generalización debe ser aditiva y backward-compatible. Conduct mantiene sus
validaciones, categorías, evidence model y contratos. Competition Reports puede
seguir en su autoridad existente durante V1; convergerlo sería otro gate, no una
condición para Profile Reports. No se crea una segunda tabla central de casos.

## 14. Autoridad

Contrato futuro no implementado:

- PostgreSQL es la única fuente de verdad.
- El actor procede de `auth.uid()` y sus capacidades server-side.
- El cliente envía `publicTargetRef`, `reportedField`, categoría, texto privado
  permitido, `operationId` y `expectedRevision` del agregado propio mostrado.
- El servidor resuelve entidad, propietario, target interno, visibilidad,
  revisión actual/histórica válida, fingerprint, relación y permisos.
- La severidad, prioridad, rol, confianza y acción nunca vienen del cliente.
- Cada command usa lock del agregado, expected revision, idempotencia, hora del
  servidor, secuencia monotónica, evento inmutable y receipt canónico.
- Realtime solo invalida; el cliente relee su read model canónico.
- Direct DML a tablas privadas queda revocado.
- Offline no confirma, no encola y no persiste texto sensible por defecto.
- Un error explícito revierte toda previsualización local.

## 15. Reporter eligibility

| Actor/canal | Comunidad Profile | Perfil privado | Auto-reporte | Canal jurídico | Regla |
| --- | --- | --- | --- | --- | --- |
| Usuario autenticado | Sí, sobre target allowlisted visible | No para outsiders | No | Posible, según decisión legal | Identidad server-side; target resuelto por servidor |
| Usuario bloqueado | Sí si ya dispone de URL pública/opaque ref legítima | No | No | Posible | Reportar no desbloquea contacto ni enumera contenido privado |
| Propietario del perfil | No contra sí mismo | Propio | Redirigir | Sí si denuncia contenido de tercero | Edición, privacidad o soporte son la vía normal |
| Miembro/Team admin/owner | Como cualquier usuario autenticado | Solo contenido legítimamente visible si se autoriza en una versión futura | No | Posible | El rol Team no concede moderación global |
| Club owner | Como usuario autenticado | Solo contenido propio por gestión | No | Posible | No ve identidad del informante |
| Árbitro | Como usuario autenticado | Propio por gestión | No | Posible | Sin privilegio extra de denuncia |
| Moderador/plataforma | Puede abrir revisión interna, no fingir reporter | Según capability | No | Escalado interno | Toda acción auditada; separación de funciones |
| Support | Puede enrutar soporte | No evidencia por defecto | No | No sin capability legal | Support no hereda moderación/evidencia |
| Anónimo | No en comunidad V1 | No | No | Pendiente de clasificación DSA | No debe exigirse cuenta si la ley aplicable requiere acceso general |
| Persona sin cuenta | No en comunidad V1 | No | No | Pendiente | Nombre/contacto solo cuando corresponda y con excepciones legales |

Decisiones resueltas de producto recomendadas:

- Un perfil público puede reportarse sin relación deportiva.
- Un perfil privado no puede descubrirse ni reportarse por un outsider.
- El auto-reporte redirige a edición, privacidad o soporte.
- Los reportes de normas de comunidad requieren autenticación.
- El target nunca se identifica mediante UUID libre enviado por el cliente.
- El canal legal no hereda automáticamente el requisito de autenticación.

## 16. Taxonomía

La selección expresa una alegación, no culpabilidad.

| Código | Label humano | Targets | Prioridad inicial | Detalle | Canal | Urgente | Ocultar al target | Duplicado | Acción posible | Conduct | V1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `impersonation` | Suplantación de identidad | Player, referee, Club, Team | Media | Requerido | Comunidad | No por defecto | Identidad reporter sí | Agrupar por campo/revisión | Request edit/unpublish | No | Sí |
| `misleading_identity` | Identidad engañosa | Todos | Normal | Requerido | Comunidad | No | Reporter sí | Agrupar | Request edit | No | Sí |
| `inappropriate_image` | Imagen inapropiada | Avatar/logo/shield | Media | Opcional | Comunidad | Según contenido | Reporter y texto | Agrupar por asset hash | Replace/hide image | No | Sí |
| `abusive_profile_content` | Contenido abusivo | Texto público | Media | Opcional | Comunidad | No por defecto | Reporter sí | Agrupar por campo | Hide/request edit | Puede coexistir, no fusionar | Sí |
| `harassment` | Acoso escrito | Texto público | Alta | Requerido | Comunidad | Sí si amenaza | Reporter/texto | Agrupar; fuentes independientes | Hide/escalate | Conduct solo si es comportamiento contextual | Sí |
| `threats_or_violence` | Amenazas o violencia | Texto/imagen | Alta | Requerido | Urgente + comunidad | Sí | Evidencia y reporter | Agrupar sin autoacción | Preserve/escalate/hide | Conduct si contexto deportivo separado | Sí |
| `discriminatory_content` | Contenido discriminatorio | Texto/imagen | Alta | Opcional | Comunidad | Posible | Reporter/texto | Agrupar | Hide/unpublish | Conduct solo contextual | Sí |
| `sexual_content` | Contenido sexual | Texto/imagen | Alta | Opcional | Safety | Sí si no consentido/menor | Todo salvo reason mínimo | Agrupar con acceso restringido | Preserve/escalate/hide | No | Sí, bloqueado por policy |
| `child_safety` | Seguridad de menores | Todos | Urgente | Mínimo guiado | Safety | Sí | Identidad/evidencia | Agrupar restringido | Preserve/escalate | No | Sí, bloqueado por policy |
| `personal_data_exposure` | Datos personales expuestos | Texto/imagen/ubicación | Alta | Campo requerido | Privacy | Sí si dirección/riesgo | Datos y reporter | Agrupar por fingerprint | Hide/request edit | No | Sí |
| `fraud_or_scam` | Fraude o estafa | Todos | Alta | Requerido | Comunidad/legal según alegación | Posible | Reporter/texto | Agrupar | Unpublish/escalate | No | Sí |
| `spam` | Spam | Texto/listing | Normal | Opcional | Comunidad | No | Reporter sí | Dedupe estricto | Unlist/request edit | No | Sí |
| `intellectual_property` | Propiedad intelectual | Imagen/texto | Normal | Requerido | Legal especializado | No | Datos claimant | Agrupar por obra/asset | Pending legal action | No | Fuera V1 |
| `illegal_content` | Contenido presuntamente ilícito | Todos | Sin inferir | Requerido por canal | Notice-and-action | Según caso | Según norma | Dedupe legal | Decisión jurídica | No | Canal separado, bloqueado |
| `other` | Otro problema | Todos | Normal | Requerido | Comunidad | Puede marcar peligro | Reporter/texto | Revisión humana | Según análisis | No | Sí, rate limit estricto |

La urgencia se deriva server-side de respuestas guiadas y revisión, no de una
`severity` arbitraria. Ningún umbral de reportes decide culpabilidad.

## 17. Snapshot de evidencia

Snapshot mínimo recomendado, inmutable y privado:

- target type y referencia pública opaca;
- target revision y server sequence resueltas;
- superficie y ruta pública canónica;
- campo reportado allowlisted;
- valor público exacto de ese campo o referencia al objeto versionado;
- content fingerprint/hash y versión del asset;
- visibility state y locale;
- categoría alegada y relación del informante calculada;
- timestamps del servidor;
- referencia a la revisión actual al decidir, separada de la denunciada.

No contiene Rating, GRL, facetas, teléfono, correo, fecha de nacimiento, lesión,
contactos, coordenadas precisas, cookies, Authorization ni secretos. El texto
del informante se guarda aparte de la evidencia objetiva y con acceso más
restringido. Una edición posterior no muta el snapshot ni cierra el caso por sí
sola; el moderador compara revisión denunciada, revisión actual y política.

## 18. Datos y minimización

| Dato | Finalidad/fuente | Acceso | Base propuesta, no aprobada | Retención/rectificación | Riesgo y medida |
| --- | --- | --- | --- | --- | --- |
| Identidad reporter | Permiso, abuso, comunicaciones; Auth | Security/legal; sistema | Interés legítimo u obligación legal según canal | Separada; corregible; eliminación sujeta a hold | Represalia: nunca al target/admin local |
| Target y propietario | Resolver contenido/notice | Moderación mínima | Prestación/legítimo interés | Según caso; alias si se suprime cuenta | Enumeración: opaque ref + resolver |
| Campo denunciado | Evidencia objetiva pública | Moderador asignado/security | Interés legítimo/obligación legal | Snapshot acotado; no full profile | Sobre-recolección: allowlist de campos |
| Descripción privada | Contexto aportado | Moderador asignado/security | Por aprobar | Caducidad corta propuesta | Datos libres: límites, cifrado, no logs |
| Fingerprint/hash | Integridad/dedupe | Sistema/moderación | Interés legítimo | Puede conservarse más que valor si se aprueba | Reidentificación: ámbito y salting adecuados |
| Moderador/asignación | Accountability | Plataforma/security | Interés legítimo/obligación | Audit trail restringido | Riesgo interno: capabilities y trazas |
| Notas internas | Investigación | Moderador/security | Por aprobar | Mínima; supresión/archivo restringido | Juicios inexactos: factualidad y corrección |
| Decisión/razón | Acción y recurso | Reporter/target en versiones distintas | Contrato/legítimo interés/obligación | Preservar lineage; rectificar por nueva revisión | Revelación: reason codes separados |
| Apelación | Recurso | Appellant/reviewer/security | Contrato/obligación posible | Ventana y archivo por aprobar | Conflicto: reviewer distinto |
| Eventos/receipts | Idempotencia/auditoría | Sistema/security; read models mínimos | Interés legítimo | Metadatos minimizados | Tokens: receipt opaco sin acceso |
| Notificaciones | Comunicar estado/acción | Destinatario | Contrato/obligación posible | Política de avisos existente | No incluir evidencia ni identidad |
| Logs/telemetría | Seguridad/salud operativa | Ops/security | Interés legítimo | Ventana corta y agregada | No free text, UUID público ni PII |

La base jurídica, avisos de privacidad, destinatarios, transferencias y plazos
requieren validación profesional antes de implementar. Procede valorar una DPIA
antes de activar debido a menores potenciales, alegaciones sensibles,
moderación, riesgo de represalia y decisiones que afectan visibilidad.

## 19. Lifecycle

No se sobrecarga un único `status`.

| Agregado | Estados propuestos | Transiciones/actor | Revisión, evento y visibilidad |
| --- | --- | --- | --- |
| Intake | `submitted`, `acknowledged`, `deduplicated`, `linked_to_case`, `withdrawn`, `closed` | Reporter envía; servidor acusa/deduplica/enlaza; retirada no borra evidencia | Revisión propia; reporter ve estado humano, no caso interno |
| Case | `open`, `triaged`, `assigned`, `under_review`, `action_pending`, `resolved`, `appeal_open`, `closed`, `archived` | Triage/moderador/security por capability | Evento inmutable; target no ve cola ni fuentes |
| Decision | `draft`, `issued`, `corrected`, `superseded` | Moderador autorizado; corrección explícita | Razón versionada; una sola decisión vigente |
| Content action | `planned`, `applied`, `failed`, `expired`, `reversed` | Command tipado del target, nunca update genérico | Receipt con revisión confirmada; canonical refetch |
| Appeal | `submitted`, `acknowledged`, `under_review`, `upheld`, `reversed`, `corrected`, `closed` | Target/reporter cuando proceda; reviewer distinto | Lineage; no revela reporter ni reactiva automáticamente |

Cada command rechaza revisión obsoleta, replays conflictivos y transición
ilegal. Timestamps son de servidor y el orden usa `server_sequence`, no hora del
dispositivo.

## 20. Moderación

Se recomienda ampliar de forma controlada `/admin/conduct` a un workspace de
moderación común, no crear otro Control Center. Las vistas y permisos siguen
separados por adaptador:

- intake reviewer: clasificación, dedupe y asignación; no aplica sanciones;
- moderator: decide contenido allowlisted y emite razones;
- security: ve identidad/evidencia restringida y urgencias;
- support: enruta solicitudes, sin evidencia por defecto;
- platform owner: gobierna capabilities/flags, no obtiene acceso implícito a
  evidencia si no tiene capability específica.

La pantalla debe mostrar solo contenido denunciado, revisión actual, política,
fuentes agrupadas, timeline y acciones aplicables. No muestra Rating, resultados,
economía, salud, contactos ni ubicación precisa.

## 21. Acciones

| Acción | V1 recomendada | Autoridad y límite |
| --- | --- | --- |
| `no_action` | Sí | Decisión razonada; informa sin declarar falsedad del reporter |
| `request_edit` | Sí | Solicita cambio; no modifica contenido automáticamente |
| `hide_reported_field` | Condicionada | Solo si target admite visibilidad de campo y restauración versionada |
| `unpublish_profile` | Sí | Oculta perfil público, mantiene cuenta y acceso privado |
| `unlist_market_listing` | Sí | Quita listing, no borra perfil ni historia |
| `restore_previous_revision` | Condicionada | Solo revisión comprobada, event/receipt y sin perder edición legítima |
| `replace_image` | Sí como solicitud/acción tipada | Asset revisionado; no aceptar uploads de evidencia |
| `suspend_publication` | Sí | Temporal, con expiración autoritativa cuando proceda |
| `preserve_private_access` | Regla | La retirada pública no elimina propiedad ni edición privada |
| `escalate_safety` / `escalate_legal` | Sí, tras policy | No promete respuesta 24/7; no notifica prematuramente al target |
| `link_existing_case` | Sí | Evita casos paralelos; conserva cada intake |
| `formal_warning` | No por defecto | Integración separada y explícita con Conduct si luego se autoriza |
| `social_restriction` | Fuera | Social Restrictions permanece `OFF`; nunca automática |

No se borra cuenta, Team, Club, membership, ownership, historia, resultado,
standing, premio, logro, caja ni cosmético.

## 22. Apelaciones

- El target puede recurrir una retirada, ocultación o restricción de
  publicación; no recurre la mera existencia de un intake sin acción.
- El informante puede pedir revisión de `no_action` solo cuando la política o el
  canal legal lo reconozca; no se promete en comunidad hasta decidirlo.
- La apelación es un objeto propio enlazado a decision/action revision.
- Replay no crea otra apelación; evidencia nueva reabre mediante command
  explícito y lineage.
- Siempre que sea viable, decide una persona distinta y se registran conflictos
  de interés.
- Una corrección supersede, no borra, la decisión anterior.
- Una reversión de contenido es command tipado con expected revision; nunca
  reactiva automáticamente contenido potencialmente peligroso.
- La identidad del informante sigue oculta.
- Conduct appeals permanece intacto; la infraestructura puede inspirar eventos
  y read models, pero no se usa con semántica falsa.

## 23. DSA

Clasificación de este gate: `NOT ESTABLISHED / NEEDS LEGAL REVIEW`.

El servicio almacena y hace públicamente accesible contenido aportado por
usuarios en varias superficies, lo que hace razonable analizar si actúa como
hosting service y, en algunas funciones, online platform. Este gate no dispone
de información jurídica/empresarial suficiente para cerrar esa clasificación.

| Tema | Clasificación | Contrato de diseño |
| --- | --- | --- |
| Art. 16, mecanismo electrónico accesible y user-friendly para contenido ilícito | `CONFIRMED REQUIREMENT` del texto para hosting; `POSSIBLY APPLICABLE` a Pachangas | Diseñar canal separado y no exigir conocimientos jurídicos innecesarios |
| Localización exacta, explicación, contacto con excepción y buena fe | `CONFIRMED REQUIREMENT` del art. 16 si aplica | URL/campo/revisión server-side; datos mínimos y excepción de contacto tratada jurídicamente |
| Acuse y comunicación de decisión | `CONFIRMED REQUIREMENT` del art. 16 si aplica | Receipts/read models canónicos |
| Tratamiento diligente, objetivo y no arbitrario | `CONFIRMED REQUIREMENT` del art. 16 si aplica | Human review, reason codes, audit y métricas |
| Statement of reasons por restricciones | `CONFIRMED REQUIREMENT` del art. 17 si aplica | Notice del target separado de notas/evidencia |
| Internal complaint handling de seis meses | `POSSIBLY APPLICABLE` | Art. 20 está en sección con exclusión micro/small del art. 19; tamaño/clasificación por validar |
| Trusted flaggers | `POSSIBLY APPLICABLE` | No crear rol propio; solo estatus oficial verificable si corresponde |
| Medidas contra abuso de notices | `POSSIBLY APPLICABLE` | Caso a caso y warning previo; no bloqueo automático por contador |
| Canal único o separado | `PRODUCT CHOICE` | Recomendado: dos entradas, comunidad autenticada y notice legal separado |
| Autoridad competente | `NEEDS LEGAL REVIEW` | CNMC es DSC español; no sustituye moderación interna ni recursos aplicables |

Recomendación: opción B, dos formularios y un backend de casos común. El canal
`Notificar contenido presuntamente ilícito` permanece fuera del V1 ejecutable
hasta confirmar clasificación, contacto, proceso, recursos y capacidad.

## 24. RGPD

El contrato aplica desde el diseño:

- finalidad especificada por canal;
- minimización de target, snapshot y free text;
- exactitud mediante revisión histórica y corrección;
- retención diferenciada, no indefinida;
- acceso por capability y necesidad de conocer;
- cifrado en tránsito y protección reforzada del texto/evidencia;
- read models separados y pseudónimos opacos;
- trazabilidad de acceso y decisiones;
- DSAR, rectificación, limitación, oposición y supresión compatibles con legal
  hold y derechos de terceros;
- telemetría agregada sin contenido ni identidad.

Los artículos 5 y 25 RGPD sustentan principios y protección desde el diseño. El
artículo 35 exige evaluar impacto cuando el tratamiento probablemente entrañe
alto riesgo. Este gate recomienda una evaluación previa a activación; no afirma
que esté completada ni decide por sí solo que sea legalmente obligatoria.

## 25. Menores

El texto legal actual indica que la web no está pensada para menores de 14 años,
pero admite que las funciones públicas requieren garantías y autorizaciones.
Eso no demuestra que no existan usuarios jóvenes ni resuelve moderación.

Antes de intake deben aprobarse:

- edad mínima contractual y prueba proporcionada;
- base jurídica/representación aplicable a reportes por o sobre menores;
- lenguaje y UX adaptados;
- acceso restringido a identidad de menor reporter;
- reglas de grooming, doxxing, sexual content, amenaza y autolesión;
- conservación/preservación y escalado externo;
- contacto con representante cuando sea seguro y lícito;
- formación y vetting de moderadores;
- no notificación al acusado cuando aumente el riesgo;
- mecanismo sin añadir fecha de nacimiento solo para esta función ni imponer
  verificación invasiva sin otra decisión.

La LOPDGDD fija reglas de consentimiento para menores cuando el consentimiento
es la base, pero no sustituye el análisis completo de base jurídica, contrato y
seguridad. Por ello se activa el stop gate indicado en la sección 2.

## 26. Urgencias

Se necesita una ruta operativa distinta para amenaza inmediata, violencia,
suicidio/autolesión, dirección expuesta, chantaje, contenido sexual no
consentido, seguridad infantil, fraude activo u orden de autoridad.

Contrato mínimo pendiente de aprobación:

- copy que indique que el canal no es un servicio de emergencias;
- instrucciones locales inmediatas cuando exista peligro;
- receptor on-call definido, cobertura horaria real y fallback;
- plazo interno medible por categoría, sin prometer 24/7 si no existe;
- preservación restringida y escalado legal/security;
- ausencia de notificación prematura al target;
- cierre, handoff y registro auditable.

Sin responsable, cobertura y protocolo, la ruta urgente es un bloqueo de
activación, no una tarea posterior.

## 27. Retención

No se heredan automáticamente los 730 días operativos y 1825 de archivo de
Conduct. Propuesta para decisión, no política aprobada:

| Capa | Propuesta de sensibilidad | Condición |
| --- | --- | --- |
| Intake/caso activo | Hasta decisión final y ventana de recurso | Legal hold suspende borrado, no amplía accesos |
| Texto libre | 90–180 días tras cierre | Eliminar antes si deja de ser necesario; preservar extracto objetivo solo si se justifica |
| Snapshot/decisión/action lineage | 12–24 meses tras cierre | Validar base, DSA/defensa de reclamaciones y proporcionalidad |
| Reporter identity linkage | Separado y con plazo mínimo necesario | Anonimizar cuando finalidad y obligaciones lo permitan |
| Eventos/receipts técnicos | Ventana definida por auditoría/idempotencia | Sin free text ni contenido sensible |
| Métricas agregadas | Largo plazo si irreversiblemente agregadas | Sin reidentificación |

Debe aprobarse una tabla definitiva por dato, purpose, base, owner, purge job,
legal hold, DSAR y evidencia de borrado. El job no puede borrar decisiones
vigentes ni convertir hashes en archivo ilimitado.

## 28. Antiabuso

- Unicidad lógica por reporter, target canónico, revisión, campo y categoría.
- El mismo `operationId` devuelve el mismo receipt; payload distinto da error.
- Una revisión nueva permite otro reporte solo si el contenido relevante cambió.
- Todos los intakes se conservan, pero se agrupan en un caso por fingerprint.
- Fuentes independientes y correlacionadas son señales de triage, no votos.
- Campañas, reciprocidad y mismo Team se etiquetan sin revelar identidades.
- Rate y burst limits transaccionales por actor, target y dispositivo/sesión
  como metadato; los límites exactos se calibran sintéticamente.
- Abuse de notices se revisa caso a caso; errores de buena fe no equivalen a
  abuso deliberado.
- Target probing devuelve errores no enumerables para privados/inexistentes.
- Payload allowlist, límites de longitud, normalización Unicode, rechazo de
  control characters, HTML activo y URLs no permitidas.
- CSRF/same-origin según canal, auth server-side, queries parametrizadas,
  sanitización de logs y output encoding.
- Separación de funciones, auditoría de acceso, revocación de sesiones y
  respuesta a cuenta de moderador comprometida.
- Races de profile edit/report, appeal/action y decisiones concurrentes usan
  expected revision y locks.

Nunca hay retirada, sanción, cambio de Rating o ranking por alcanzar `N`.

## 29. RLS/RBAC

Leyenda: `own` = solo su read model/acción; `summary` = razón/acción aplicable;
`cap` = capability explícita y necesidad de conocer; `no` = denegado.

| Actor | Submit | Own report | Target decision | Reporter ID | Evidence | Triage/assign | Decide | Content action | Appeal | Correct/archive/export |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| anon | legal pending | no | no | no | no | no | no | no | no | no |
| authenticated reporter | yes public | own | no | own | no | no | no | no | reporter review if policy | own export subject to rights |
| target | no self | no | summary | no | reported content only | no | no | owner edit, not moderation | own | own rights request |
| Team admin/owner | user rules | own | own Team summary | no | no | no | no | normal Team edit only | own Team | no moderation export |
| Club admin/owner | user rules | own | own Club summary | no | no | no | no | normal Club edit only | own Club | no moderation export |
| referee | user rules | own | own profile summary | no | no | no | no | normal own edit only | own | no |
| intake reviewer | internal | cap | minimal | pseudonym only | public snapshot | cap | no | no | no | no |
| moderator | internal | cap | cap | no by default | cap | cap | cap | allowlisted cap | review if independent | correct/archive cap; no bulk export |
| platform_admin | user rules | own | summary by role | no by default | no by default | only explicit cap | explicit cap | explicit cap | own | no implicit export |
| platform_owner | user rules | own | summary | no by default | no by default | explicit cap | explicit cap | explicit cap | own | governance, not evidence by default |
| support | route only | support ticket | public summary | no | no | no | no | no | route | no moderation export |
| security | internal | cap | cap | cap | cap | cap | safety decision cap | safety/legal cap | conflict-safe | cap + audited export |
| service_role | no browser | system job | system | system minimum | system minimum | jobs only | no human decision | typed jobs | no | retention/health jobs audited |

Implementación futura: tablas privadas sin grants a `anon`/`authenticated`;
RPC mínima; `SECURITY DEFINER` solo cuando sea imprescindible, search path fijo,
auth y capabilities dentro de función; views expuestas con seguridad explícita;
`service_role` nunca en navegador.

## 30. Realtime

Eventos públicos de Realtime contienen únicamente:

- audience/recipient;
- opaque aggregate reference;
- event kind no sensible;
- revision y server sequence;
- timestamp del servidor.

No contienen reporter, texto, evidencia, notas, decisión jurídica, target
privado ni reason completo. Al recibir un evento el cliente invalida solo el
read model afectado y hace canonical refetch. `SUBSCRIBED` y reconexión releen
estado; WAL no es autoridad. Caché local es derivada y nunca confirma una
operación.

## 31. Notificaciones

Eventos de producto previstos: recepción, asignación interna, decisión, acción,
notice al target, apelación, resolución, restauración, urgencia interna y
vencimiento.

Se reutiliza `pachanga_user_notifications` con dedupe key, revisión, secuencia y
payload mínimo. Recomendación V1:

- in-app obligatorio para decisiones, acciones y apelaciones;
- sin push real;
- sin email real;
- sin evidencia, reporter, free text ni datos sensibles;
- mandatory security/sanction notices no se ocultan por preferencias;
- delivery failure no convierte una acción en éxito para el cliente.

Push/email requieren decisión y QA operativa separadas. No se envían en este
gate.

## 32. UX

### Reporter

Entrada contextual en menú de perfil público, no navegación primaria ni CTA en
cada tarjeta. Flujo: motivo, campo, detalle guiado, peligro inmediato, resumen,
confirmación autoritativa, receipt opaco y estado propio. Lenguaje humano, foco,
lector de pantalla, teclado, portrait y Mobile Game Landscape.

Offline: no confirmar, no encolar, no escribir texto sensible en localStorage;
permitir copiar antes de salir y reintentar explícitamente tras reconexión. Un
doble submit usa el mismo `operationId`.

### Reporter read model

Referencia, fecha, categoría humana, target público resumido, recepción, estado
comprensible, decisión final cuando proceda y vía de revisión. Nunca moderador,
otras fuentes, señales, notas o datos privados.

### Target read model

Contenido afectado, policy/reason, acción, duración, fecha, revisión, statement
comprensible y recurso. Nunca reporter, descripción privada, otros reportes,
correlaciones o scoring. Safety/legal puede retrasar el notice.

### Moderación

Cola común con filtros por edad, target, categoría, duplicados y prioridad;
comparación revision denunciada/actual; timeline, reason codes, acciones y
apelaciones. La UX no confunde bloquear, silenciar, soporte ni Conduct.

## 33. Capacidad operativa

Simulación mensual de sensibilidad, no previsión real. Supuestos:

| Escenario | Reportes/1.000 perfiles | Duplicados | Urgentes/casos | Apelaciones/casos | Min/caso | Min/apelación |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Bajo | 2 | 20% | 1% | 2% | 6 | 15 |
| Base | 10 | 35% | 3% | 8% | 12 | 30 |
| Alto | 30 | 50% | 8% | 20% | 25 | 60 |

`Casos = reportes x (1 - duplicados)` y `horas = casos x minutos/caso +
apelaciones x minutos/apelación`, dividido por 60.

| Perfiles | Escenario | Reportes | Casos | Urgentes | Apelaciones | Horas/mes |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 100 | Bajo | 0,20 | 0,16 | 0,00 | 0,00 | 0,02 |
| 100 | Base | 1,00 | 0,65 | 0,02 | 0,05 | 0,16 |
| 100 | Alto | 3,00 | 1,50 | 0,12 | 0,30 | 0,93 |
| 1.000 | Bajo | 2,00 | 1,60 | 0,02 | 0,03 | 0,17 |
| 1.000 | Base | 10,00 | 6,50 | 0,20 | 0,52 | 1,56 |
| 1.000 | Alto | 30,00 | 15,00 | 1,20 | 3,00 | 9,25 |
| 5.000 | Bajo | 10,00 | 8,00 | 0,08 | 0,16 | 0,84 |
| 5.000 | Base | 50,00 | 32,50 | 0,97 | 2,60 | 7,80 |
| 5.000 | Alto | 150,00 | 75,00 | 6,00 | 15,00 | 46,25 |
| 10.000 | Bajo | 20,00 | 16,00 | 0,16 | 0,32 | 1,68 |
| 10.000 | Base | 100,00 | 65,00 | 1,95 | 5,20 | 15,60 |
| 10.000 | Alto | 300,00 | 150,00 | 12,00 | 30,00 | 92,50 |

La capacidad máxima no se fija por usuarios: la activación exige que el P95
modelado consuma como máximo el 60% de horas humanas disponibles, cobertura de
urgencias aprobada y una persona de backup. Campañas se simulan aparte porque
pueden concentrar demanda aunque se dedupliquen.

| Estado | Criterio orientativo, pendiente de SLA aprobado |
| --- | --- |
| `UNKNOWN` | Sin staffing, telemetría o policy válida; intake debe estar OFF |
| `OK` | Urgentes sin asignar 0; oldest normal <=24 h; appeals overdue 0; backlog <=60% de capacidad semanal |
| `WARNING` | Oldest 24–72 h o backlog 60–80%, o cobertura cercana al límite |
| `CRITICAL` | Urgente sin asignar más allá del plazo aprobado, oldest >72 h, backlog >80% o apelación vencida |

Kill switch: desactiva nuevo intake y mantiene lectura, notices, apelaciones y
trabajo de casos existentes. No borra ni falsea receipts.

## 34. Feature flags

Set futuro recomendado, no creado:

| Flag conceptual | Dependencia | Estado inicial |
| --- | --- | --- |
| `profile_reports_foundation_enabled` | Schema, RLS, read models, observability | OFF |
| `profile_reports_moderation_enabled` | Moderador/capacity/policies | OFF |
| `profile_reports_appeals_enabled` | Decisions/notices/reviewer | OFF |
| `profile_reports_intake_enabled` | Foundation + moderation + appeals cuando aplique + safety | OFF |
| `profile_reports_public_entrypoints_enabled` | Intake + target allowlist | OFF |
| `profile_reports_illegal_content_notice_enabled` | Gate jurídico y operativo propio | OFF |

Dependencias fail-closed, activación por RPC de plataforma con operationId,
expected revision, evento y auditoría; nunca `UPDATE` directo. El kill switch no
impide atender casos ya aceptados. `conduct_reports_enabled` no activa Profile.
Flags actuales no cambian.

## 35. Activación

Plan futuro, no ejecutado:

1. Fase 0: schema/authority desplegados, todo OFF, cero UI/reportes.
2. Fase 1: fixtures sintéticos, Control Center y moderación interna; cero
   usuarios reales.
3. Fase 2: Preview/staging autenticado con targets sintéticos, intake privado,
   apelación, Realtime y cleanup.
4. Fase 3: shadow/private beta allowlisted, cola/SLA/capacity monitorizados,
   sin acciones automáticas.
5. Fase 4: activación gradual por target type, límites bajos y kill switch.

El canal jurídico exige gate propio. No hay fecha de lanzamiento ni piloto real
autorizado.

## 36. Riesgos

| Riesgo | Severidad | Mitigación/stop |
| --- | --- | --- |
| Exponer reporter o menor | Crítica | Identidad separada, capabilities security, tests negativos, no Realtime/notice |
| Moderación sin capacidad | Crítica | `UNKNOWN` => intake OFF; staffing, backup y urgencias obligatorios |
| Mezclar Conduct y contenido | Alta | Adaptadores y taxonomías separadas sobre case authority común |
| Duplicar autoridad | Alta | Un agregado común; Competition existente fuera del cambio V1 |
| Retirada automática por campaña | Alta | Human decision, clustering, independencia de fuentes, no N=culpa |
| DSA mal clasificado | Alta | Gate jurídico; canal legal OFF; no declaración de cumplimiento |
| Retención excesiva | Alta | Tabla por dato, purge auditable, legal hold acotado, DPIA evaluation |
| IDOR/enumeración | Alta | Opaque ref, resolver server-side, errores no distinguibles |
| Stale content/action race | Alta | Target revision, aggregate locks, expected revision y receipt |
| Perfil oculto pero datos derivados visibles | Alta | Acción transaccional sobre todas las proyecciones allowlisted + canonical refetch |
| Moderador comprometido | Alta | Separation of duties, audit access, revocation, no bulk export |
| Fake success PWA | Alta | No offline queue, explicit errors, rollback optimistic preview |

## 37. Decisiones resueltas

| Decisión | Resultado congelado por este gate |
| --- | --- |
| Existe hueco de producto | Sí |
| Arquitectura | `GENERALIZED_MODERATION_AUTHORITY` |
| Autoridad paralela | No |
| Intake | Específico Profile/Content |
| Case authority | Única y generalizada de forma compatible desde Conduct |
| Comunidad sin relación deportiva | Sí, autenticado sobre target público allowlisted |
| Perfil privado outsider | No |
| Auto-reporte | Redirigir a edición/privacidad/soporte |
| Target/actor/severity | Resueltos por servidor |
| Uploads V1 | No |
| Realtime | Invalidation only + canonical refetch |
| Offline | Fail-closed, sin cola ni fake success |
| Auto-sanctions | No |
| Rating/GRL/Ranking/Rewards/Billing | Inmutables respecto de reportes |
| Competition report | Autoridad actual, fuera de Profile V1 |
| Venue/open match | Diferidos, no incluidos por comodidad |
| Canal comunitario vs legal | Separados en UX; infraestructura común solo tras gate legal |

## 38. Decisiones pendientes

| Decisión bloqueante | Quién debe resolver | Recomendación | Efecto si no se resuelve |
| --- | --- | --- | --- |
| Política de menores y safety | Alberto + legal/safety responsable | Aprobar edad, representación, notices, escalado y acceso | Intake permanece OFF por stop gate |
| Responsable de moderación | Alberto | Nombrar primary y backup con capabilities | Queue health `UNKNOWN`; intake OFF |
| Cobertura y SLA de urgencias | Alberto + security/legal | Definir horario real, fallback y mensajes sin promesa 24/7 | Categorías graves no pueden abrirse |
| Clasificación DSA | Asesoría jurídica | Determinar hosting/online platform, tamaño y obligaciones | Canal legal y claims bloqueados |
| Canal notice-and-action | Legal + producto | Formulario separado, accesible según aplicabilidad | `illegal_content` queda fuera |
| Identidad/contacto legal | Titular + legal | Completar responsable y contacto operativo | No se puede comunicar ni escalar correctamente |
| Base jurídica por tratamiento | Asesoría privacidad | Matriz final por dato/finalidad | Persistencia bloqueada |
| Retención y legal hold | Legal/privacy + security | Aprobar plazos por capa y purge | Schema/retention job no ejecutables |
| DPIA | Responsable de tratamiento/asesoría | Hacer screening y DPIA si corresponde antes de beta | Activación no autorizada |
| Términos/normas de comunidad | Producto + legal | Publicar reglas y reason codes versionados | Moderación no tiene criterio contractual |
| Recurso del reporter contra no-action | Producto + legal | Admitir al menos en canal legal cuando aplique | Reporter status incompleto |
| Target allowlist final | Alberto + safety/legal | Empezar por Market, Referee, Club y Team; Venue diferido | Entry points no activables |
| Plazos de apelación | Legal + producto | Alinear con canal/tipo de decisión | Actions que requieran recurso permanecen OFF |
| Acciones temporales y expiración | Producto + moderación | Solo publicación, no cuenta/Team | Content action authority incompleta |

## 39. Backlog #179–181

- #179: `HISTORICAL ISSUE TEXT SUPERSEDED` y
  `OUTSIDE PROFILE REPORTS SCOPE`. Referee Assignments se desplegó después. No
  se cierra ni modifica.
- #180: `PARTIALLY SUPERSEDED`, `PUBLIC EXPOSURE STILL SEPARATE` y
  `OUTSIDE PROFILE REPORTS SCOPE`. Competition Discipline private beta existe;
  la exposición pública sigue separada. No se cierra ni modifica.
- #181: `PRODUCT/BUSINESS DECISION REQUIRED` y
  `OUTSIDE PROFILE REPORTS SCOPE`. No se implementan pagos arbitrales.
- #167, #168 y #169: `PHYSICAL QA OPEN/PENDING`; emulación no los cierra.

## 40. Conclusión

El main auditado confirma un hueco real: existe moderación contextual Conduct y
un reporte específico de competición, pero no Profile Reports genérico. La
arquitectura segura queda definida como intake específico sobre una autoridad
de casos generalizada y única. La implementación no puede comenzar hasta que
se aprueben las decisiones de menores, urgencias, operación, retención,
privacidad y aplicabilidad legal enumeradas.

```text
PROFILE REPORTS V1 GATE: BLOCKED BY PRODUCT OR LEGAL DECISION
```
