# Competition Configuration Center V1 Report

## Estado

`LOCAL RELEASE CANDIDATE / REMOTE RELEASE PENDING`

Wave 5A incorpora una capa de autoria reutilizable que termina siempre en la
`RuleRevision` canonica de R1. No crea `LeagueSettings`, `DisciplineSettings` o
`RefereeSettings` paralelos. Presets, modo sencillo, modo avanzado, clonacion y
comparacion solo producen o inspeccionan borradores; la publicacion materializa
una revision inmutable con fecha efectiva, checksum y documento humano
derivado.

## Trazabilidad

| Dato | Valor |
| --- | --- |
| Fecha local | `2026-08-26` |
| Base | `4fa505fd7323d72398e4ee637e818205b0d6fdab` |
| Rama | `codex/competition-configuration-center-v1` |
| PR | `#202` (draft durante el gate local) |
| Ledger base | `152` |
| Migraciones Wave 5A | `6` |
| Ledger local | `158` |
| Node | `v24.16.0` |
| Supabase CLI | `2.107.0` |

## Migraciones forward-only

1. `20260826123000_competition_configuration_center_schema_v1.sql`
2. `20260826123100_competition_configuration_rules_v1.sql`
3. `20260826123200_league_wizard_v2_commands.sql`
4. `20260826123300_competition_configuration_commands_v1.sql`
5. `20260826123400_competition_configuration_engine_policy_v1.sql`
6. `20260826123500_competition_configuration_control_center_v1.sql`

Las migraciones nacen con `competition_configuration_center_enabled=false` y
`league_wizard_v2_enabled=false`. Instalarlas no crea competiciones, no abre
superficies publicas y no ejecuta el canonical legacy backfill.

## Modelo de autoridad

```text
Preset o RuleRevision fuente
        -> ConfigurationDraft privado
        -> validacion + health + impact
        -> confirmacion del organizador
        -> RuleSet/RuleRevision canonica congelada
        -> R4A-R4D, R5 y Assignments consumen esa revision
```

Todas las escrituras entran por
`command_pachanga_competition_configuration_v1(operationId,
expectedRevision, action, payload, clientMetadata)`. PostgreSQL resuelve actor,
capability, Competition, Edition, flags, punto de congelacion, referencias,
hora, secuencia, revision e impacto. El navegador no puede enviar una
RuleRevision completa ni calculos de autoridad.

## Autoridad almacenada

- borradores, receipts y eventos privados;
- invalidaciones Realtime publicas pero acotadas por usuario/Competition;
- presets como datos de copia, no como reglamentos vivos;
- resumen, health, comparador e impacto derivados de la configuracion;
- documento humano derivado de la revision con version, fecha y checksum;
- RuleRevision publicada inmutable y reconstruible.

El orden canonico usa revision/secuencia e identificador estable. Ninguna
lectura de ultimo estado depende solo de `created_at`.

## Modos y presets

| Capacidad | Resultado |
| --- | --- |
| Sencillo | opciones esenciales y valores seguros |
| Avanzado | doce secciones y politicas soportadas |
| Liga F7 amateur estandar | disponible |
| Liga F5 rapida | disponible |
| Liga F11 | disponible |
| Liga de futbol sala | disponible |
| Clonar RuleRevision | copia solo reglas, nunca resultados o participantes |
| Comparar | diferencias agrupadas por dominio |

El preset queda registrado como procedencia del borrador. Cambiar un preset en
el futuro no modifica ninguna revision publicada.

## Configuracion soportada

- identidad, organizer Team/Club, privacidad, zona, temporada y slug;
- F5, F7, F11 y futbol sala;
- una vuelta o ida/vuelta, 4-20 equipos y una division;
- plantillas, elegibilidad, duracion, buffer, descanso, sede, timezone y horario;
- 3/1/0 u otros valores validos, resultado y confirmacion bilateral;
- desempates soportados por R4C, sin Fair Play ficticio;
- goleadores obligatorios, opcionales o desactivados;
- aplazamientos, retrasos, no-show, suspension y reanudacion compatibles con R4D;
- catalogo R5 para amarilla, segunda amarilla, roja y azul;
- ciclos, acumulacion, sanciones, comite y apelaciones soportadas;
- arbitro ninguno/opcional/obligatorio con `MAIN_REFEREE`;
- asignacion, reconfirmacion, modalidad, zona, relacion Club y reemplazo;
- observacion arbitral de tarjetas, incidencias y marcador sin transferir la
  autoridad de resultado, standings, sanciones o Rating;
- tarifa gratis, voluntaria, fija o negociable sin procesar pagos;
- visibilidad privada/participantes y futuras superficies publicas bloqueadas
  por flags globales.

`MANUAL_ASSISTED`, `HYBRID`, pagos y Tournament Engine se muestran como futuras
capacidades, nunca como acciones disponibles.

## Validacion y health

`CompetitionConfigurationHealth` devuelve estado, errores, advertencias,
funciones apagadas y proxima accion. La publicacion bloquea contradicciones,
entre ellas:

- sede obligatoria sin sede ni TBD;
- arbitro obligatorio con Assignments apagado;
- BLUE sin politica temporal;
- acumulacion con threshold cero;
- apelacion con deadline invalido;
- goleadores requeridos mientras estan desactivados;
- resultado automatico sin confirmacion compatible;
- no-show sin outcome/marcador;
- plantilla minima mayor que maxima;
- fechas fuera de la Edition.

## Freeze points e impacto

| Estado efectivo | Proteccion |
| --- | --- |
| Draft | editable |
| Registro abierto | bloquea cambios estructurales incompatibles |
| Registro cerrado | congela equipos, roster y estructura |
| Calendario publicado | congela formato, vueltas, pairing y scheduling |
| Primer resultado oficial | congela puntuacion y desempates aplicables |

Un cambio posterior crea otra RuleRevision con `effectiveFrom`. El impacto
cuenta partidos futuros, jugadores, counters, sanciones, assignments,
resultados, standings e incompatibilidades. No existe aplicacion retroactiva
silenciosa.

## Integracion con motores

- R4A-R4D toman politicas estructurales, scheduling, resultado e incidencias de
  la revision efectiva.
- R5 materializa el catalogo disciplinario desde la RuleRevision.
- Referee Assignments valida uso, aceptacion, reconfirmacion, requisitos,
  readiness y tarifa contra la RuleRevision.
- Guardas transaccionales serializan cambio de reglas contra registro,
  calendario, resultado oficial, evento disciplinario y confirmacion arbitral.

## Seguridad

- borradores, receipts y eventos viven en `private`;
- `anon` y `authenticated` no tienen `INSERT`, `UPDATE` o `DELETE` directos;
- `authenticated` solo ejecuta RPCs de comando/lectura autorizadas;
- actor desde `auth.uid()` y capabilities desde PostgreSQL;
- Team owner participante no hereda permiso sobre las reglas del organizer;
- APIs `no-store`, same-origin, payloads por allowlist y sin service role;
- la tarifa fija privada se elimina de read models no autorizados;
- Realtime invalida y relee; el payload WAL no es autoridad;
- offline conserva lectura confirmada y no encola mutaciones deportivas.

## Concurrencia

Las siete carreras focales producen `1 winner / 1 stale o conflict`:

1. dos ediciones del mismo borrador;
2. publicar frente a editar;
3. abrir registro frente a cambio estructural;
4. publicar calendario frente a cambiar reglas;
5. resultado oficial frente a cambiar puntuacion;
6. evento disciplinario frente a cambiar catalogo;
7. confirmar Assignment frente a cambiar politica arbitral.

## Gate local

| Gate | Resultado |
| --- | --- |
| Configuration Center | `14/14 PASS` |
| Concurrencia | `7/7 PASS` |
| League Wizard V2 | `18/18 PASS` |
| Bateria completa | `504/504 PASS` |
| SQL/RLS | `PASS` |
| Regresiones R4A-R4D/R5/Assignments | `PASS` |
| Fresh bootstrap | `158/158 PASS` |
| Upgrade `152 -> 158` | `PASS` |
| Equivalencia fresh/upgrade | `PASS` |
| Hash de esquema | `e2cea456c640dfbd3a73fe2f2a6b9e80738585ac7cdf2ea7d19f17e88f647e0f` |
| Typecheck | `PASS` |
| Build | `PASS`, 50 rutas |
| Lint focalizado | `PASS` |
| Lint global | deuda previa: `22 errores / 18 warnings` |
| PWA standalone local | `PASS` |
| Visual | 9 viewports, 0 overflow raiz, 0 imagenes rotas |

## Invariantes

Las pruebas protegen Rating V2, assessments, Rewards, Player Cosmetics, Team
Cosmetics, Conduct y Billing. Wave 5A no cambia formulas, facetas, ratings,
evidencias sociales, recompensas, pagos ni datos historicos.

## Pendiente del release remoto

- aplicar y leer las seis migraciones en staging;
- completar E2E autenticado y cleanup de staging;
- fusionar PR y aplicar migraciones productivas forward-only;
- activar los dos flags privados, manteniendo superficies publicas OFF;
- smoke efimero y cleanup productivo;
- deployment y readback final.
