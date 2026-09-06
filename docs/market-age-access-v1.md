# Edad y acceso al mercado

Decisión de producto acordada el 6 de septiembre de 2026: acceso personal al mercado y organización de retos desde los 18 años. La fecha de nacimiento es privada y declarada por el usuario; no constituye verificación documental de identidad.

- Los menores pueden registrarse, crear equipos y jugar con sus miembros.
- No pueden buscar equipos o partidos en el mercado, publicarse, recibir invitaciones de mercado ni organizar encuentros externos.
- Un administrador adulto puede organizar esos encuentros para un equipo creado por un menor. Los miembros menores conservan acceso al partido de su equipo.
- Sin fecha de nacimiento, el acceso externo queda pendiente de completar el perfil. La pertenencia al equipo sigue disponible.
- La mayoría de edad se calcula con la fecha de Madrid, sin almacenar una edad que quede desactualizada.

## Persistencia y publicación pendiente

La migración `20260906121319_market_age_access_v1.sql` agrega la fecha al perfil social, recupera la fecha previa del perfil de jugador cuando existe y protege lecturas y operaciones en el servidor. Las restricciones también cubren las tablas que admite consultar el cliente. No se elimina ningún equipo, partido o miembro.

Al aplicarla, se desactivan los anuncios personales de menores o sin fecha y los anuncios de equipos sin administrador adulto. Completar la fecha o incorporar un adulto habilita la posibilidad de publicar; no republica anuncios automáticamente. La migración debe desplegarse coordinadamente con el formulario nuevo y revisarse contra las funciones vigentes antes de producción. Clientes antiguos sin fecha deberán recargar para completar el dato.

Cambios preparados localmente; no aplicados en producción.

## Validación local

- 53 pruebas de contratos: fecha válida, cumpleaños 18, registro y contratos sociales existentes.
- SQL transaccional sobre una base QA independiente: creación de equipo por un menor, bloqueo de búsqueda/publicación/revisión de solicitudes, privacidad de la fecha, ocultación al corregir edad, administrador adulto añadido al equipo, envío y aceptación reales de reto, y lectura del partido externo por el miembro menor. Los datos de prueba se revierten.
- Navegador móvil con respuestas sintéticas: registro, restricciones para menor y fecha ausente sin cargar datos de mercado, acceso normal del adulto y navegación Perfil → Configurar mercado público, incluida recarga.
- TypeScript y ESLint sin errores. Supabase security advisors sobre esa base QA sin incidencias de nivel warn/error.

Pruebas reproducibles: `tests/market-age-access.test.ts`, `tests/market-age-access-db.sql`, `tests/market-age-access-e2e.mjs` y `tests/profile-market-entry-e2e.mjs`. Las pruebas de navegador requieren un servidor local configurado con el proyecto ficticio indicado en sus cabeceras. No utilizan cuentas reales.
