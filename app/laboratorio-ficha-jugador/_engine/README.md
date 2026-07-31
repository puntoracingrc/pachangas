# Motor de ficha universal de jugador

Implementación local y no enlazada del sistema de evaluación de jugadores.

## Versiones

- `football-rating-v1`
- `initial-test-v1`
- `advanced-test-v1`
- `current-form-v1`

## Flujo

1. `calculateInitialRatings(input)` valida que las modalidades sumen 100, modera respuestas técnicas por experiencia/frecuencia, calcula `baseRatings`, aplica ajuste provisional de frecuencia a `currentRatings` y guarda respuestas originales.
2. `calculateAdvancedRatings(input)` integra respuestas opcionales con pesos por pregunta, multiplicadores de modalidad, posición y coherencia. Completar módulos aumenta fiabilidad, pero no concede puntos por sí mismo.
3. `calculateCurrentRatings(input)` sustituye el ajuste provisional por estilo de vida cuando está completo y aplica limitaciones actuales solo a `currentRatings`.
4. `calculateOverall(ratings, position)` calcula GRL por posición con pesos que suman 1.

## Reglas conservadas

- Edad, altura, peso, posición y modalidad no modifican directamente atributos.
- `null` representa desconocido y nunca se transforma en cero.
- La autoevaluación queda limitada a 92 por atributo y 65 de fiabilidad.
- Lesiones recuperadas no modifican nada.
- Limitaciones actuales no alteran `baseRatings`.
- Todos los cálculos internos conservan decimales; la UI redondea solo al mostrar.

## Persistencia local

La ruta `app/laboratorio-ficha-jugador` guarda el borrador en `localStorage` con la clave `pachangas-player-evaluation-lab-v3`. La pantalla enseña una ficha limpia para el jugador; el desglose interno queda dentro del motor y los tests.

## Integración pendiente

No se han creado migraciones ni se ha conectado el motor al registro real. Para producción habrá que definir tablas o columnas de respuestas versionadas, consentimiento privado, caducidades y permisos antes de enlazar esta ruta con perfiles reales.
