# Independent Player Social Profile V1

Fecha: 2026-09-02 (Europe/Madrid)

## Resultado

V3F incorpora una identidad social mínima que puede existir sin equipo y sin
crear una ficha deportiva. PostgreSQL es la única autoridad; el onboarding
solo conserva un borrador local y sustituye ese borrador por el read model
canónico después de cada confirmación.

## Autoridad

- Tabla: `public.pachanga_social_player_profiles_v1`.
- Historial: `private.pachanga_social_player_profile_revisions_v1`.
- Evidencia: receipts y events privados de Social Team Core.
- Lectura: `get_my_pachanga_social_profile_v1()`.
- Escritura: `command_pachanga_social_profile_v1(action, expected_revision,
  operation_id, payload, client_metadata)`.
- Acciones: `profile.create`, `profile.update`, `profile.avatar.confirm` y
  `profile.availability.update`.
- Actor, fecha, revisión y secuencia se resuelven en servidor.
- `anon` y `authenticated` no tienen INSERT, UPDATE o DELETE directo.

## Datos y privacidad

El perfil admite nombre visible, avatar seguro, posición principal y
secundaria, modalidad preferida, zona general, días, franja, bio y preferencias
sociales. No contiene Rating, GRL, facetas, votos, sanciones, teléfono,
coordenadas, dirección, roles ni datos bancarios.

## Precedencia

1. La identidad social aporta nombre/avatar/posición de presentación cuando no
   existe una autoridad deportiva más específica.
2. `pachanga_player_profiles` sigue gobernando ficha deportiva, Rating y datos
   propios del equipo; V3F nunca lo sobrescribe ni lo recalcula.
3. La carta pública y sus cosméticos siguen usando sus read models existentes.
4. Mercado continúa siendo opt-in mediante sus comandos propios; guardar el
   perfil o entrar en un equipo no publica al jugador.

## Cliente, caché y Realtime

- Inicio y `/perfil` leen el snapshot canónico reducido.
- La caché `pachangas-social-profile-v3f:<userId>` es una copia versionada de
  lectura, no una segunda autoridad.
- Realtime invalida por entidad y obliga a releer el snapshot.
- Offline permite editar el borrador, pero responde
  `Necesitas conexión para confirmar esta acción.` y nunca muestra éxito.

## Validación local

- Perfil sin equipo y perfil mínimo: cubiertos.
- Replay y conflicto de revisión: cubiertos por SQL/RPC.
- Rating/GRL enviados por cliente: rechazados por payload allowlisted.
- Escritura de perfil ajeno y DML directo: bloqueados.
- PostgreSQL runner: PASS con `ROLLBACK`.
- Tests V3F: PASS.

Staging autenticado: PASS para creación sin equipo, actualización, revisión,
idempotencia, caché derivada y offline fail-closed. Producción: pendiente del
release coordinado V3F.
