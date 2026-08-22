# Official UI V2 - Guia de revision para Alberto

Duracion estimada: 10-15 minutos.

Esta revision es visual. No hace falta comprobar SQL, RLS, migraciones ni checksums. La Preview usa fixtures aislados y no requiere modificar produccion.

## Preview

- Base congelada: `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app`
- Comparativa completa: `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/laboratorio-official-ui-v2?surface=comparativa`

## Recorrido recomendado

1. **Inicio desktop** (1 minuto)
   `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/laboratorio-official-ui-v2?surface=inicio`

2. **Partido y Proximo** (1 minuto)
   `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/laboratorio-official-ui-v2?surface=partido&pane=proximo`

3. **Alineacion** (1 minuto)
   `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/laboratorio-official-ui-v2?surface=partido&pane=alineacion`

4. **Resultado** (1 minuto)
   `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/laboratorio-official-ui-v2?surface=partido&pane=resultado`

5. **Mercado** (1 minuto)
   `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/laboratorio-official-ui-v2?surface=mercado`

6. **Carta y escudo** (2 minutos)
   Carta: `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/laboratorio-official-ui-v2?surface=carta`
   Escudo: `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/laboratorio-official-ui-v2?surface=equipo`

7. **Portrait** (1 minuto)
   Abrir Inicio y Mercado con el telefono vertical. Comprobar que se sienten como una aplicacion completa y no como desktop comprimido.

8. **Inclinar el telefono** (2 minutos)
   Abrir Alineacion y girar a horizontal. Debe sentirse que has entrado en modo juego: campo protagonista, rail propio, sin footer ni doble navegacion.

9. **Mercado de arbitros** (1 minuto)
   `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/laboratorio-referee-platform?surface=market`

10. **Perfil y propuesta arbitral** (1 minuto)
    Perfil: `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/laboratorio-referee-platform?surface=private`
    Propuesta: `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/laboratorio-referee-platform?surface=proposed`

11. **Demo World** (1 minuto)
    `https://pachangas-cwjjnfiab-persianas-almar-web-s-projects.vercel.app/demo`

## Preguntas de aprobacion visual

Responder solo a estas decisiones humanas:

1. El Inicio parece mas claro que antes?
2. Se reconoce rapidamente la accion principal de cada pantalla?
3. El modo horizontal parece realmente un videojuego?
4. La carta y el escudo tienen suficiente protagonismo?
5. El Mercado esta demasiado cargado o tiene la densidad adecuada?
6. Los fondos y efectos tienen la intensidad adecuada?
7. La navegacion resulta natural en desktop, vertical y horizontal?
8. Hay algo importante que parezca escondido?

## Respuesta esperada

La aprobacion solo se considerara concedida con una instruccion posterior inequivoca equivalente a:

```text
APROBADA VISUALMENTE PARA PRODUCCION
```

Comentarios, preferencias o el cierre de esta guia no autorizan merge ni produccion.
