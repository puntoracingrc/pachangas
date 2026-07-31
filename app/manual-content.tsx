const manualFlows = [
  {
    audience: "Todos",
    title: "Primera entrada",
    intro: "Al abrir Pachangas IQ puedes revisar una demo completa o entrar con Google para usar un grupo real.",
    steps: [
      "La demo muestra jugadores, partidos, historial, reservas, pagos, fichas y valoraciones para probar la web sin crear nada.",
      "Para crear grupos, partidos, campos o administrar datos necesitas entrar con Google.",
      "Cuando creas un grupo real, empieza limpio: sin jugadores, sin campos y sin partidos de demo.",
      "Si llegas con un enlace de invitación, entras directamente al grupo correspondiente.",
    ],
  },
  {
    audience: "Todos",
    title: "Crear o entrar en un grupo de pachangas",
    intro: "El grupo de pachangas es el espacio privado donde se guardan jugadores, campos, partidos e historial.",
    steps: [
      "Si entras con una invitación, la web te pide Google si hace falta y después vuelve al grupo correcto.",
      "Si ya tienes fichas propias en otros grupos, la app te propone entrar con una copia inicial de la mejor ficha.",
      "Por defecto se elige la ficha con mayor media; si empata, más partidos jugados; si vuelve a empatar, la más reciente. Las fichas inactivas se pueden elegir, pero no salen como recomendadas.",
      "Si empiezas desde cero, pulsa Crear > Grupo, escribe el nombre y guarda. El primer usuario queda como Owner / Admin.",
      "Cuando creas un grupo real, empieza limpio: sin jugadores, sin campos y sin partidos de demo.",
      "Comparte la invitación del grupo con los iconos de copiar o WhatsApp para que entren los demás.",
    ],
  },
  {
    audience: "Jugador",
    title: "Tu cuenta y tu ficha",
    intro: "Cada jugador registrado puede tener una ficha propia ligada a su usuario.",
    steps: [
      "Entra con Google y cambia tu nombre visible en el grupo, por ejemplo Alberto.",
      "Pulsa Crear > Ficha jugador para crear o editar tus datos: nombre, teléfono Bizum, foto, posición preferida y estado.",
      "Al importar una ficha se copia nombre, foto y encuadre, fecha de nacimiento, posición preferida, portero fijo y media inicial.",
      "No se copian goles, partidos jugados, victorias, forma, historial, votos concretos ni lesión. En el grupo nuevo esos datos empiezan de cero.",
      "Mientras no haya valoraciones propias del grupo, la media se marca como importada. Cuando el grupo ya tenga votos reales, pasa a del grupo.",
      "Puedes añadir foto desde archivo o cámara; la app intenta centrar el avatar y puedes arrastrarlo dentro de la carta antes de guardar.",
      "Solo tú y los admins podéis editar tu ficha. Las valoraciones las hacen compañeros, no puedes votarte a ti mismo.",
    ],
  },
  {
    audience: "Admin",
    title: "Prueba gratuita y suscripción",
    intro: "Cada grupo puede probar la app con partidos reales antes de pagar.",
    steps: [
      "El owner del grupo puede crear y finalizar 2 partidos gratis.",
      "Cuando se intenta crear, guardar o finalizar el tercer partido, la app pide activar un plan de Stripe.",
      "Solo paga el owner del grupo. Los admins y jugadores pueden usar el grupo sin pagar una cuenta propia.",
      "Plan mensual: 5,99 € al mes. Plan anual: 64,99 € al año.",
      "Fórmula del trial: partidos gratis restantes = 2 - partidos finalizados del grupo sin suscripción activa.",
      "Fórmula de acceso: si la suscripción está activa o en periodo trialing de Stripe, el grupo puede crear y finalizar partidos sin límite.",
    ],
  },
  {
    audience: "Admin",
    title: "Campos y ajustes iniciales",
    intro: "Antes de crear partidos conviene guardar los campos habituales y los ajustes básicos del sitio.",
    steps: [
      "Pulsa Crear > Campo para guardar un campo con nombre, precio y modalidad por defecto.",
      "El nombre del campo debe elegirse desde una sugerencia de Google Places para guardar una dirección real, placeId y ubicación aproximada.",
      "Esa ubicación sirve después para filtrar el mercado de fichajes por proximidad al partido sin pedir direcciones privadas a jugadores.",
      "También sirve para consultar Google Weather y mostrar la previsión del tiempo cuando el partido está dentro de los próximos 7 días.",
      "Para controlar consumo, la previsión se reutiliza 24 horas si falta más de 1 día y 2 horas durante las últimas 24 horas antes del partido.",
      "Google Places solo se usa al buscar o seleccionar direcciones; si el campo ya tiene placeId y coordenadas guardadas, la app reutiliza esos datos.",
      "La modalidad puede ser fútbol sala, fútbol 7 o fútbol 11.",
      "En Configurar puedes cambiar las instrucciones del grupo y los colores de los equipos.",
      "Desde Configurar también puedes borrar campos guardados que ya no usas o que se crearon mal. Los partidos históricos conservan el nombre del campo.",
      "Los colores elegidos se aplican a bloques, listas, fichas, campo y goleadores.",
      "También puedes activar Aporte app por Bizum para mostrar una referencia separada del precio del campo.",
    ],
  },
  {
    audience: "Admin",
    title: "Crear partido",
    intro: "Un partido nuevo nace como borrador para evitar que la gente se apunte antes de estar bien configurado.",
    steps: [
      "Pulsa Crear > Partido y revisa campo, fecha, modalidad, precio y reservas.",
      "La temporada no se elige a mano: se calcula desde la fecha y se guarda en la ficha del partido.",
      "Cada temporada empieza en septiembre y termina en agosto del año siguiente.",
      "Mientras no pulses Guardar partido, no aparece en Próximos partidos y nadie puede marcar asistencia.",
      "Al guardar se activan confirmaciones, compartir, alineación, resultado y pago.",
      "Si el campo tiene ubicación verificada, verás Tiempo previsto con temperatura, lluvia y viento aproximados durante el partido.",
      "El enlace del partido se comparte con Copiar link o WhatsApp.",
      "Si te equivocas o el partido no se juega, puedes borrarlo con papelera y doble confirmación.",
    ],
  },
  {
    audience: "Jugador",
    title: "Apuntarte a un partido",
    intro: "Un partido solo acepta respuestas cuando el admin lo ha guardado.",
    steps: [
      "Si el partido está en borrador, verás que la alineación y las confirmaciones están pendientes.",
      "Si hay un partido anterior pendiente y su fecha todavía no ha pasado, la inscripción del siguiente partido queda cerrada hasta después de esa hora.",
      "Cuando el partido está guardado puedes marcar Voy, Duda o No.",
      "El orden de Voy se guarda con día y hora. Ese orden decide titulares, reservas y lista de espera.",
      "Si cambias de Voy a Duda o No, la app avisa de que perderás tu posición; si hay reservas, el primero sube.",
      "Si estás marcado como lesionado, apareces como No voy hasta que se quite la lesión.",
    ],
  },
  {
    audience: "Jugador",
    title: "Reservas y pago",
    intro: "Las reservas pueden quedar fuera o contar como asistentes según configure el admin.",
    steps: [
      "Si Reservas van y pagan está activo, las reservas dentro del máximo cuentan para el pago.",
      "Si no está activo, las reservas quedan como suplentes por orden y no entran en el reparto.",
      "El turno de pago del campo y el importe por jugador se calculan cuando el admin cierra la alineación.",
      "Hasta cerrar la alineación, Toca, Paga y Pagados aparecen pendientes porque la lista todavía puede cambiar.",
      "Una vez cerrada, el pagador aparece destacado con el dólar dorado.",
      "Cada jugador puede verse como pagado cuando se marque su dólar en verde.",
      "La cuota de la app, si el admin decide repartirla, se muestra aparte como aporte por Bizum al owner y no se suma al precio del campo.",
      "Fórmula del campo: toca por jugador = precio del campo / jugadores que pagan campo.",
      "Fórmula de aporte app: aporte por jugador = coste mensual o anual elegido / jugadores activos del grupo.",
    ],
  },
  {
    audience: "Admin",
    title: "Alineaciones",
    intro: "La app propone equipos y coloca fichas en el campo según modalidad y posiciones.",
    steps: [
      "Los porteros fijos se separan en equipos diferentes cuando hay dos disponibles.",
      "Puedes mover jugadores manualmente de un equipo a otro con las flechas.",
      "Aleatorio reparte al azar; Equilibrado intenta compensar medias y posiciones.",
      "Cerrar alineación bloquea la alineación para jugadores; Abrir alineación permite cambios de nuevo.",
      "Si alguien se baja, el primer reserva sube automáticamente aunque la alineación estuviera cerrada.",
    ],
  },
  {
    audience: "Admin",
    title: "Finalizar partido",
    intro: "Finalizar archiva el partido en historial y actualiza estadísticas.",
    steps: [
      "Primero rellena el resultado. Hasta entonces no se pueden asignar goles.",
      "Los goles se introducen por equipo y la app no deja superar el marcador de cada lado.",
      "Cualquier miembro puede subir una foto del partido como recuerdo; solo un admin puede quitarla.",
      "Al pulsar Finalizar partido, el partido pasa al historial.",
      "Después de finalizar, campo, fecha, modalidad, precio y reservas quedan bloqueados.",
      "Si hubo un error, aún puedes corregir asistencia y goleadores para ajustar el histórico.",
    ],
  },
  {
    audience: "Todos",
    title: "Historial y ranking",
    intro: "La memoria del grupo vive en los partidos cerrados, el ranking y las fichas.",
    steps: [
      "Próximos partidos muestra solo partidos abiertos y guardados.",
      "Historial muestra los últimos partidos con separadores por mes, foto en miniatura y resumen de pago y goles.",
      "El ranking se puede filtrar por la temporada guardada en cada partido, de septiembre a agosto, y ordenar por media, goles, partidos o ganados.",
      "Cada carta del ranking abre la ficha del jugador para consultar detalle, estado y evolución.",
    ],
  },
  {
    audience: "Todos",
    title: "Mercado de fichajes",
    intro: "El mercado vive en una página separada del grupo privado para encontrar jugadores por zona, horario y modalidad.",
    steps: [
      "Cada jugador decide si publica su ficha en el mercado desde su propia ficha. Es opt-in: si no lo activas, no apareces.",
      "Se publican datos base: nombre, foto, encuadre, edad, posición, media, zonas donde puedes jugar, disponibilidad y si aceptas invitaciones puntuales o de grupo.",
      "Cada zona se elige con Google Places y tiene radio propio: solo esta población, +5, +10, +20, +30 o +50 km.",
      "Si pones Sabadell con solo esta población no apareces para Barcelona; si pones Sabadell +20 km, puedes aparecer para campos dentro de ese radio.",
      "El mercado filtra primero con distancia aproximada por coordenadas guardadas, sin llamar a Google Routes ni consumir rutas de pago.",
      "No se publican votos concretos, teléfono Bizum, historial privado del grupo ni datos internos de pagos.",
      "Los jugadores normales pueden ver el mercado y probar filtros, pero no pueden invitar a nadie.",
      "Owners y admins podrán invitar desde un partido guardado usando la dirección verificada del campo, la modalidad y la disponibilidad del jugador.",
      "Si el jugador acepta una invitación puntual, entra solo a ese partido. Al finalizar, deja de tener acceso al grupo salvo que después reciba una invitación completa al grupo.",
      "Cuando un jugador entra a otro grupo con una ficha previa, se copia una base inicial; a partir de ahí su media, forma, goles e historial evolucionan dentro del nuevo grupo.",
    ],
  },
  {
    audience: "Jugador",
    title: "Valoraciones",
    intro: "La media del jugador sale de valoraciones por facetas en escala 0-100, estilo ficha de fútbol.",
    steps: [
      "Las facetas son ritmo, tiro, pase, regate, defensa y físico. Los porteros tienen facetas específicas. Todo se muestra de 0 a 100.",
      "Una ficha recién creada se puede valorar antes de que juegue su primer partido, por si ya conoces al jugador.",
      "Si no lo valoras y el jugador completa su primer partido, las valoraciones se cierran hasta que llegue a 3 partidos jugados.",
      "Después de votar, tu voto queda cerrado hasta que ese jugador juegue otros 3 partidos.",
      "En el listado aparece si la valoración está abierta o cerrada, y la ficha muestra la evolución.",
      "La placa de la ficha cambia por media: bronce hasta 64, plata de 65 a 74 y oro desde 75.",
    ],
  },
  {
    audience: "Todos",
    title: "Media, forma y equilibrio",
    intro: "La app separa la calidad real del jugador de su ritmo temporal para evitar castigos injustos.",
    steps: [
      "Media real = promedio de las facetas valoradas por compañeros. Si todavía no hay votos, se usa el valor base de la ficha.",
      "La media real no baja por no jugar, lesionarse o no apuntarse. Representa calidad: tiro, pase, defensa, físico o facetas de portero.",
      "Forma actual = porcentaje temporal visible de 0 a 100 calculado con los últimos 5 partidos jugados, la racha sin venir, lesiones y fiabilidad; no se muestra hasta que el jugador tenga al menos un partido finalizado.",
      "Nota reciente de partido = 6.2 más ajustes por victoria, derrota ajustada o amplia, goles, portería a cero y pocos o muchos goles encajados.",
      "Antes de tener partidos, la app usa una forma neutral interna del 100% solo para equilibrar, pero la ficha muestra Forma pendiente para no inventar un dato.",
      "Lesionado no castiga la media: marca el estado En recuperación y baja la forma de forma suave hasta que vuelva a jugar.",
      "Fiabilidad = 100% menos 7 puntos por cada cancelación tarde, con mínimo 70%. Afecta al equilibrio, no a la media.",
      "Valor para equilibrar = media real multiplicada por forma actual. Ejemplo: media 80 y forma 92% cuentan como 74 para montar equipos.",
      "El equilibrio también suma goles por partido, victorias, experiencia, posición y bonus de portero/defensa para que el reparto sea más realista.",
    ],
  },
  {
    audience: "Admin",
    title: "Gestión de jugadores",
    intro: "Los admins pueden crear fichas y mantener limpia la plantilla.",
    steps: [
      "Con Crear > Ficha jugador cada usuario puede crear su ficha. Los admins pueden ayudar a corregir datos si hace falta.",
      "Un jugador registrado puede reclamar o crear su propia ficha.",
      "Portero fijo ayuda a que el sistema lo coloque siempre en portería.",
      "Lesionado bloquea el Voy y muestra el icono de hospital en listados.",
      "Borrar jugador lo deja fuera del grupo, pero no elimina su histórico ni su ranking pasado.",
    ],
  },
  {
    audience: "Admin",
    title: "Configuración profunda y copias",
    intro: "Cuando el grupo ya funciona, Configurar reúne permisos, estética, instrucciones y rescates.",
    steps: [
      "En Miembros puedes ver usuarios del grupo y su rol actual.",
      "Solo el owner puede cambiar un jugador a Admin o devolverlo a Jugador desde Configurar.",
      "Solo el owner puede generar una invitación de admin para alguien que todavía no está registrado.",
      "Desde Configurar puedes crear una copia manual, ver las últimas copias del servidor y restaurar una copia si algo se ha borrado por error.",
      "La app crea copias automáticas al guardar o finalizar un partido, y también justo antes de borrar un grupo.",
      "El grupo se puede borrar con papelera y doble confirmación para evitar errores.",
    ],
  },
];

export function ManualContent() {
  return (
    <div className="manual-flow-list">
      {manualFlows.map((flow) => (
        <article key={flow.title} className="manual-flow-card">
          <header>
            <b>{flow.title}</b>
            <span>{flow.audience}</span>
          </header>
          <p>{flow.intro}</p>
          <ol>
            {flow.steps.map((step) => (
              <li key={step}>{step}</li>
            ))}
          </ol>
        </article>
      ))}
    </div>
  );
}
