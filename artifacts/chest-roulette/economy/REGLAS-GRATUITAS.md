# Tiradas gratuitas: decisiones del usuario

6 de septiembre de 2026. Reglas acordadas para la integración pendiente; este documento no concede tiradas reales.

| Origen | Concesión | Acumulación |
| --- | --- | --- |
| Test inicial completado | Una por jugador, una sola vez | Se guarda hasta usarla |
| Test secundario/avanzado completado | Otra por jugador, una sola vez | Se guarda hasta usarla |
| Actividad semanal | Una por semana si ha participado en un partido en los últimos 30 días | Se acumula sin caducar |
| Eventos futuros | Reservado; sin campañas ni concesiones activas | Se definirá por evento |

Al pasar 30 días sin jugar cesan las nuevas concesiones semanales. El saldo de tiradas ya obtenido permanece utilizable. Al volver a participar se recupera la elegibilidad; nunca se concede más de una por semana por participar en varios partidos o equipos.

Los tests ya son de una sola realización: la migración `20260905084509_restore_initial_assessment_profile_onboarding_v1.sql` rechaza una nueva operación para un test completado. Reenviar la misma operación es un reintento técnico, no un nuevo test. La concesión única de la tirada debe respetar ese comportamiento existente; no se habilita repetir tests.

Las tiradas gratuitas tienen las mismas probabilidades y premios que las pagadas. Mientras haya gratuitas disponibles se consume una gratuita antes de cobrar puntos. La recomendación económica sigue siendo 15 puntos fijos por tirada pagada para todos; no depende del inventario.

## Criterios para la integración

- La participación debe estar confirmada por datos del servidor; apuntarse, recibir una invitación o que el equipo juegue sin el jugador no basta.
- Validar finalización de los tests canónicos `initial` y `advanced` en el servidor. No confiar en flags del navegador ni en reinicios del formulario.
- Concesiones persistentes e idempotentes por jugador y origen: test inicial, test avanzado y semana. Distinguirlas de operaciones de gasto para que un reintento nunca duplique un premio.
- La acumulación semanal no debe depender de abrir la web esa semana: el servidor deberá emitir o reconciliar las semanas elegibles aunque el jugador no visite la ruleta.
- Para concretar el calendario se propone semana de lunes a domingo en Europe/Madrid y ventana móvil de 30 días. Elegibilidad al inicio de la semana o al confirmarse una participación posterior dentro de ella; una única concesión por semana. Estos son detalles técnicos propuestos, no preferencias expresas del usuario.
- La migración debe definir una fecha de activación y un tratamiento explícito de tests ya completados. No emitir premios retroactivos de semanas anteriores al lanzamiento por accidente.
- Conservar origen e historial de cada concesión para futuras campañas; no activar eventos ficticios ni dar saldo inicial de demostración.

## Impacto económico medido

Se han añadido 7.200 temporadas simuladas con precio 15, una gratuita semanal para jugadores que juegan todas las semanas y dos gratuitas de tests en la primera semana. Se consumen todas las gratuitas y se reinvierten todos los puntos; no se simula que el jugador reserve tiradas.

Con un partido semanal y 50% de victorias:

| Colección al comenzar | Sin gratuitas: giros/semana | Con estas gratuitas: giros/semana |
| --- | ---: | ---: |
| Vacía | 1,90 | 4,40 |
| Completa | 2,17 | 4,81 |

Incluye los giros gratuitos y los pagados que permiten sus premios. No es una promesa semanal. Las 54 gratuitas del escenario corresponden a 52 semanas elegibles y 2 tests únicos; en años posteriores no se repiten los tests. Una persona inactiva no recibe 52 semanales.

La acumulación permite gastar muchas tiradas juntas, aunque no aumenta la cantidad total concedida. Por tanto, una sesión puede ser muy larga tras meses ahorrando; no debe confundirse con duplicación de saldo ni resolverse eliminando las tiradas guardadas.

El precio 15 sigue ofreciendo un consumo positivo del saldo de puntos incluso con toda la colección. La semanal convierte la ruleta en una actividad más frecuente: aproximadamente cuatro o cinco giros por semana en el escenario indicado. Esta frecuencia es una decisión de producto; mantenerla exige conservar los pesos y conversiones evaluados o repetir el estudio si cambian.

Reproducción: `python3 artifacts/chest-roulette/economy/weekly.py`. Resultados: `weekly-results.json`.
