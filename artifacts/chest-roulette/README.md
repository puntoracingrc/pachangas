# Ruleta de premios — integración de producción

Ruta de producto: `/ruleta`; `/laboratorio-ruleta` comparte la misma implementación conectada.

La RPC `pachanga_roulette_v1` autentica al jugador y decide cada sorteo, cobra una vez, conserva cofres sellados y concede los premios del catálogo activo al abrirlos. Usa el saldo y el inventario cosmético existentes. El navegador solo decide el movimiento decorativo de la cinta. Se han retirado las tablas de premios y saldos ficticios del prototipo.

Precio fijo: 15 puntos. Mismas probabilidades para todos (60/25/10/4/1). Una gratuita por test inicial y otra por avanzado, incluidos los tests existentes completados antes del lanzamiento. Una semanal acumulable por participación confirmada en los últimos 30 días, desde la semana de activación. Semana de lunes a domingo, Europe/Madrid. Se reconcilian semanas elegibles sin exigir visitas a la app; al dejar de jugar conserva lo acumulado. No hay eventos futuros activados.

Los cofres de ruleta no generan logros ficticios. El nuevo origen de inventario conserva una FK al cofre de ruleta; el historial de puntos usa el identificador del cofre y metadata `source=roulette`. Los cofres de logros siguen su circuito existente. Los duplicados se convierten al abrir según el catálogo sellado; los combinados entregan sus puntos base más la conversión.

Pruebas locales:
- Migración en una copia local de esquema y catálogo, separada de las bases utilizadas por otros tasks.
- `tests/reward-roulette-db.sql`: permisos, identidad, premios únicos de tests, gratuitas semanales, inactividad, rollback por saldo insuficiente, reintentos, duplicados combinados, origen del inventario y apertura masiva.
- `tests/reward-roulette-concurrency.mjs`: dos cobros simultáneos con saldo para uno; dos reintentos simultáneos de la operación ganadora.
- `tests/reward-roulette-browser.mjs`: sesión sintética, transporte RPC conectado a PostgreSQL local; gratuitas primero, seguir girando, débito, persistencia tras recarga, resumen y suma visible al volver. No envía solicitudes a producción. Requiere `PLAYWRIGHT_MODULE` apuntando al módulo Playwright instalado y Chrome local.
- Capturas móvil/resumen/escritorio en `release/`. Emulación de navegador; no equivalen a una prueba en teléfono físico.

Estudios reproducibles en `economy/`. La publicación y verificación remota se documentarán al terminar el despliegue.
