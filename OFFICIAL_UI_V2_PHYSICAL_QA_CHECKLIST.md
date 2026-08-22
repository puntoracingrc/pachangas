# Official UI V2 - Physical QA Checklist

Estado actual: `PHYSICAL_QA_PENDING`

Esta lista exige un telefono real. Chrome DevTools, Playwright, responsive mode, simulacion CSS y emulacion de notch no cuentan como QA fisica.

Comprobacion de disponibilidad del 2026-08-22:

- Android real disponible: **NO**; no hay dispositivo USB visible y `adb` no esta instalado.
- iPhone real disponible: **NO**; no hay iPhone/iPad USB visible y `xcrun devicectl` no esta disponible en este Mac.
- No se ha sustituido esta ausencia por emulacion ni se ha marcado ningun caso como aprobado.

## 1. Preview y limites

- Preview visual congelada: `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app`
- Fixtures visuales: `/laboratorio-official-ui-v2` y `/laboratorio-referee-platform`.
- Demo aislada: `/demo`.
- No usar produccion ni crear datos reales.
- No introducir nuevas decisiones esteticas durante esta QA.

## 2. Registro Android

| Dato | Valor |
| --- | --- |
| Disponible | `NO / PENDING` |
| Modelo |  |
| Version Android |  |
| Version Chrome |  |
| Fecha |  |
| Browser | `PENDING` |
| PWA instalada | `PENDING` |
| Observaciones |  |

## 3. Registro iPhone

| Dato | Valor |
| --- | --- |
| Disponible | `NO / PENDING` |
| Modelo |  |
| Version iOS |  |
| Safari/WebKit |  |
| Fecha |  |
| Safari | `PENDING` |
| PWA Add to Home Screen | `PENDING` |
| Observaciones |  |

## 4. Matriz obligatoria por dispositivo

Marcar cada celda como `PASS`, `FAIL` o `BLOCKED`. El valor inicial es `PENDING`.

| Superficie | Browser portrait | Browser landscape | PWA portrait | PWA landscape | Giro conserva estado | Touch/scroll | Observaciones |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Inicio | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Partido | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Proximo | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Alineacion | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Resultado | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Mercado | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Mercado Arbitros | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Ranking | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Avisos | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Carta | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Escudo | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Perfil arbitral | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Control Center movil | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |
| Demo World | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |  |

## 5. Mobile Game Landscape

| Comprobacion | Android | iPhone | Observaciones |
| --- | --- | --- | --- |
| Activa `MOBILE_GAME_LANDSCAPE` | PENDING | PENDING |  |
| No muestra escritorio reducido | PENDING | PENDING |  |
| No muestra footer | PENDING | PENDING |  |
| No hay doble navegacion | PENDING | PENDING |  |
| Acciones principales alcanzables | PENDING | PENDING |  |
| Notch/barras no cubren controles | PENDING | PENDING |  |
| Contenido principal cabe | PENDING | PENDING |  |
| El giro no recarga la ruta | PENDING | PENDING |  |
| Se percibe como modo juego | PENDING | PENDING |  |

## 6. Alineacion fisica

| Comprobacion | Android | iPhone | Observaciones |
| --- | --- | --- | --- |
| Campo visible y util | PENDING | PENDING |  |
| Jugadores seleccionables | PENDING | PENDING |  |
| Banquillo accesible | PENDING | PENDING |  |
| Drag y tap precisos | PENDING | PENDING |  |
| Scroll lateral controlable | PENDING | PENDING |  |
| Guardar permanece gated | PENDING | PENDING |  |
| Giro conserva seleccion | PENDING | PENDING |  |

## 7. Carta y escudo

| Comprobacion | Android | iPhone | Observaciones |
| --- | --- | --- | --- |
| Objeto visual protagonista | PENDING | PENDING |  |
| Selector accesible | PENDING | PENDING |  |
| Scroll correcto | PENDING | PENDING |  |
| Tap preciso | PENDING | PENDING |  |
| Estado `NEW` visible | PENDING | PENDING |  |
| Guardar permanece gated | PENDING | PENDING |  |
| Safe area no tapa controles | PENDING | PENDING |  |

## 8. Teclado real

Probar busqueda de Mercado, bio arbitral, filtros, formularios y mensajes.

| Comprobacion | Android | iPhone | Observaciones |
| --- | --- | --- | --- |
| Campo activo visible | PENDING | PENDING |  |
| Error visible | PENDING | PENDING |  |
| Guardar visible | PENDING | PENDING |  |
| Confirmar visible | PENDING | PENDING |  |
| Cancelar visible | PENDING | PENDING |  |
| Borrador persiste tras giro | PENDING | PENDING |  |

## 9. PWA, offline y reconexion

| Comprobacion | Android | iPhone | Observaciones |
| --- | --- | --- | --- |
| Instalacion/A2HS correcta | PENDING | PENDING |  |
| Icono y launch correctos | PENDING | PENDING |  |
| Offline muestra estado real | PENDING | PENDING |  |
| Ninguna escritura parece confirmada offline | PENDING | PENDING |  |
| Reconexion recupera lectura | PENDING | PENDING |  |
| Service Worker sin error | PENDING | PENDING |  |
| 0 warnings de hidratacion | PENDING | PENDING |  |

## 10. Giro y persistencia

Ejecutar `portrait -> landscape -> portrait` conservando ruta, tab, filtros, seleccion, formulario, modal, arbitro, carta y alineacion.

Confirmar expresamente:

- 0 escrituras duplicadas.
- 0 peticiones deportivas duplicadas.
- 0 navegaciones involuntarias a Inicio.

## 11. Registro de defecto fisico

Para cada `FAIL` registrar:

1. Dispositivo, OS y browser/PWA sin identificadores personales.
2. Ruta y pasos minimos reproducibles.
3. Captura sin datos personales.
4. Error runtime, Service Worker o consola remota si existe.
5. Correccion minima propuesta.
6. Test de regresion.
7. Revalidacion en emulacion y en el mismo dispositivo.

No usar un defecto fisico para abrir otro rediseno.
