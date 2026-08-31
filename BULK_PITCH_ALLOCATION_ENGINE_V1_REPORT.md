# Bulk Pitch Allocation Engine V1 Report

Estado: `RELEASE CANDIDATE / STAGING CERTIFIED`

Fecha: 2026-08-31 CEST

## Autoridad deportiva

Wave 9B no crea Match ni horario paralelos. La identidad sigue siendo
`CanonicalMatch + CompetitionMatchContext + ScheduleItem`:

- R4B decide partido, fecha y hora;
- Wave 9B decide Venue/Pitch autorizado y reserva;
- Wave 9A materializa hold, reserva y binding;
- R4D gestiona cambios posteriores.

Los 128 horarios de Demo V3.5 son identicos antes y despues. Un partido sin
campo produce conflicto o queda TBD si su RuleRevision lo permite; nunca se
desplaza silenciosamente.

## Freeze, plan y determinismo

El modelo append-only incluye plan, input freeze, revisiones, items,
constraints, locks, conflictos, quality, holds, validaciones, diffs, receipts,
eventos e invalidaciones. El freeze persiste checksums de Match, Schedule,
Pool, Availability, Reservation, Binding y RuleRevision.

Algoritmo: `season-venue-allocator-v1`. Se persisten version, seed, checksum de
entrada/salida, presupuesto y candidatos. Misma version + seed + input produce
el mismo resultado; no depende de `Math.random`, `Date.now` ni orden accidental
de SQL.

Resultados diferenciados:

- `VENUE_ALLOCATION_UNSATISFIABLE`;
- `VENUE_ALLOCATION_SEARCH_BUDGET_EXHAUSTED`;
- `VENUE_ALLOCATION_PARTIAL`;
- `VENUE_ALLOCATION_INPUT_STALE`.

## Constraints y quality

Hard constraints cubren horario fijo, disponibilidad, overlaps, conflictos
parent/child, modalidad, duracion, buffer, estados, autorizacion, ventana,
RuleRevision, binding existente, locks y timezone. Nunca se publican hard
violations.

Soft constraints cubren preferencias de Venue/Pitch, localia, cambios minimos,
uso de bloques, equilibrio de slots/Pitches, distancia autorizada, grupos,
final destacada y continuidad. Quality expone asignados/no asignados, uso
recurrente, cambios, utilizacion, balance, overrides, locks, conflictos,
warnings, score y checksum; React no lo recalcula.

## Holds y publicacion

`allocation.hold` reutiliza Wave 9A, usa server time, expira en un maximo de dos
horas y limita el lote a 150 salvo override de plataforma. La expiracion libera
slots, marca el plan stale e invalida una vez.

`allocation.publish` es atomica: consume/reutiliza holds, crea o reutiliza
reservas, crea un unico VenueMatchBinding y emite evidencia. Si falla un item,
crea cero reservas y cero bindings. El replay devuelve los mismos IDs,
checksums y receipt. Un binding existente se conserva como lock implicito.

## Verificacion

- esquema fresh y upgrade `220 -> 228`: identicos, hash
  `7b9a69ed794f9f71dc0a0efc91c9ae75b20f79fef9c4261eb5c19a4a1d0fee12`;
- SQL/RLS/idempotencia: `PASS`;
- concurrencia: seis carreras, un ganador canonico por carrera;
- staging: holds concurrentes, validacion y publicacion con cero dobles
  reservas/bindings y cero cambios horarios;
- escala certificada: 10.000 planes, 100.000 items, 50.000 locks, 50.000
  reservas y 100.000 bindings/invalidaciones; cinco tamanos de Competition,
  diez metricas p50/p95 bajo 2.500 ms y rollback completo.

Produccion permanece pendiente del release coordinado de Wave 9B.
