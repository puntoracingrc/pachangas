# League Wizard V2 Report

## Estado

`V2 IMPLEMENTED / AUTHENTICATED STAGING PASS`

League Wizard V2 sustituye la autoria de diez pasos por doce secciones sin
romper el endpoint V1. La compatibilidad V1 delega en la misma autoridad V2 y
los borradores historicos reciben las nuevas secciones con valores seguros
forward-only.

## Doce pasos

1. Identidad.
2. Modalidad.
3. Edicion y fechas.
4. Formato y equipos.
5. Plantillas y elegibilidad.
6. Partidos y puntuacion.
7. Horarios, sedes y descanso.
8. Resultados, goleadores y desempates.
9. Aplazamientos, retrasos y no-show.
10. Disciplina.
11. Arbitros.
12. Visibilidad, resumen y publicacion.

## Compatibilidad

- `command_pachanga_league_private_beta_v2` es el comando nativo.
- `command_pachanga_league_private_beta_v1` conserva su firma publica y delega
  internamente en V2.
- la operacion de inicializacion amplia un draft V1 sin borrar datos previos;
- los diez pasos antiguos se proyectan sobre las doce secciones actuales;
- finalizar el wizard no abre registro ni fabrica una Competition paralela;
- la Edition sigue en draft hasta que la operacion canonica abra el registro.

## Modos y flujo

El wizard ofrece modo sencillo y avanzado. Ambos guardan exclusivamente
intenciones semanticas y convergen en el mismo borrador de configuracion.

```text
Elegibilidad privada
 -> preset o autoria vacia
 -> doce pasos
 -> validacion y resumen humano
 -> confirmacion explicita
 -> RuleRevision congelada
```

La UI conserva estado al cambiar de modo, usa navegacion lateral en desktop y
composicion compacta en portrait/landscape. Los controles de disciplina y
arbitros son reales cuando sus flags privados estan activos; pagos, torneos y
pairing manual/hibrido siguen no disponibles.

## Acciones permitidas

- iniciar wizard;
- actualizar una seccion con `expectedRevision`;
- aplicar preset;
- validar;
- finalizar contra la autoridad canonica;
- cancelar el borrador.

Cada accion usa `operationId`, version de cliente/worker y modo instalado. El
servidor devuelve receipt, revision confirmada y snapshot; el cliente descarta
cualquier previsualizacion si la operacion falla.

## Seguridad y concurrencia

- identidad, entitlement, organizer y bundle se resuelven en PostgreSQL;
- un organizer solo puede mantener la cantidad de editions permitida;
- `LEAGUE_PRIVATE_BETA_V1` debe estar vigente y sin expirar;
- direct writes a drafts/canon quedan revocados;
- repetir `operationId` devuelve el mismo receipt;
- dos dispositivos sobre la misma revision producen un ganador y un stale;
- Realtime invalida la entidad y relee el wizard completo;
- offline permite lectura confirmada, nunca una finalizacion aparente.

## QA

| Gate | Resultado |
| --- | --- |
| Contrato Wizard V2 | `18/18 PASS` |
| Doce pasos | `PASS` |
| Adaptador V1 | `PASS` |
| SQL/RLS | `PASS` |
| Idempotencia | `PASS` |
| Concurrencia | `PASS` |
| Desktop `1440x900` | `PASS` |
| Portrait `390x844` | `PASS` |
| Landscape `844x390` | `PASS` |
| Viewports extremos requeridos | `PASS` |
| PWA standalone | `PASS` |
| Controles cortados | `0` |
| Overflow raiz | `0` |
| Staging Team preset | `PASS` |
| Staging Club advanced | `PASS` |
| Staging idempotencia/concurrencia | `PASS` |
| Staging cleanup | `PASS`, flags restaurados y 0 drafts activos |

El footer sticky se protege frente a la navegacion movil y la barra de acciones
reserva espacio lateral en game landscape. Son regresiones visuales cubiertas
por el gate de Wave 5A.

## Limites deliberados

- League Private Beta continua invite-only.
- Public registration/calendar/standings/discipline continuan OFF.
- Maximo configurable: 20 equipos en este producto.
- Solo division unica y round robin automatico.
- Asistentes y mesa arbitral son futuros.
- Pachangas IQ no procesa la tarifa arbitral.
- Tournament Engine y Draw/Bracket Engine no se han iniciado.
