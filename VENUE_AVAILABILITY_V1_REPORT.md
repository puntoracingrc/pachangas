# Venue Availability V1 Report

Fecha: 2026-08-30 CEST

## Contrato

La disponibilidad se calcula en PostgreSQL a partir de templates recurrentes,
excepciones, timezone IANA, buffers y claims activos. El navegador no decide si
un slot esta libre. `tstzrange` y la exclusion GiST impiden solapamientos aun
cuando dos dispositivos leen simultaneamente el mismo estado.

## Modelo

- `pachanga_venue_availability_templates`: regla semanal versionada.
- `pachanga_venue_availability_exceptions`: cierre o apertura puntual.
- `pachanga_venue_pitch_claims`: hold o reserva que ocupa el recurso.
- Cada Venue conserva timezone; los comandos reciben instantes UTC y el
  servidor valida la ventana local, DST, excepciones y buffers.

Acciones autoritativas: crear, actualizar y desactivar template; crear y
cancelar excepcion. Mantenimiento del Pitch prevalece sobre disponibilidad.

## Precedencia

1. Venue y Pitch deben estar activos.
2. La modalidad solicitada debe estar permitida.
3. Debe existir un template activo que cubra el intervalo local.
4. Una excepcion de cierre invalida el slot; una apertura explicita lo habilita
   bajo las mismas reglas de recurso.
5. Buffers amplian el rango de conflicto.
6. Hold o reserva activos ganan sobre una lectura anterior.

## Lectura y cache

`get_pachanga_venue_availability_v1` devuelve un read model canonico. La PWA
puede leer la ultima disponibilidad cacheada, pero offline no puede crear ni
confirmar operaciones. Realtime solo invalida y provoca refetch; el payload WAL
no se aplica como estado.

## Migraciones

| Version | Nombre | SHA-256 |
| --- | --- | --- |
| `20260830145049` | `venue_availability_templates_exceptions_v1` | `65cad385bdd6558d67db17cbcd44532d93c29f8ee02d4a3840a333a74390655e` |
| `20260830145058` | `venue_rls_realtime_notifications_v1` | `7157dd0dafc3a005def0a4a367f47c9b7701f78b930dc86eff9ebc01ecfdc4db` |

## Validacion local

- Timezone, DST, template, excepcion, modalidad y buffers: PASS.
- Availability edit vs request submit: un ganador y un stale/conflict: PASS.
- Pitch maintenance vs reservation acceptance: PASS.
- 40.000 templates + 10.000 excepciones en DB aislada.
- Availability query p50/p95: `2.424 / 5.079 ms`.
- Conflict detection p50/p95: `60.176 / 64.711 ms`.
- Rollback y cleanup del corpus: PASS.

## Produccion

Availability esta `ON` en settings revision `8`. El canary productivo creo un
template, valido el slot, rechazo una revision obsoleta y completo el flujo de
reserva dentro de una transaccion con `ROLLBACK`. El readback posterior devolvio
cero templates, excepciones y claims. La exclusion GiST y los buffers siguen
siendo la autoridad de conflicto; Realtime solo invalida y provoca refetch.

Las superficies `/campos`, `/reservas`, gestion Club, Control Center y las seis
perspectivas Demo V3.4 pasaron la matriz productiva sin overflow, requests
fallidas ni errores de consola.
