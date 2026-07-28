const manualFlows = [
  {
    audience: "Todos",
    title: "Primera entrada",
    intro: "Al abrir Pachangas IQ puedes revisar una demo completa o entrar con Google para usar un equipo real.",
    steps: [
      "La demo muestra jugadores, partidos, historial, reservas, pagos, fichas y valoraciones para probar la web sin crear nada.",
      "Para crear equipos, partidos, campos o administrar datos necesitas entrar con Google.",
      "Cuando creas un equipo real, empieza limpio: sin jugadores, sin campos y sin partidos de demo.",
      "Si llegas con un enlace de invitación, entras directamente al equipo correspondiente.",
    ],
  },
  {
    audience: "Todos",
    title: "Crear o entrar en un equipo",
    intro: "El equipo pachanguero es el espacio privado donde se guardan jugadores, campos, partidos e historial.",
    steps: [
      "Si entras con una invitación, la web te pide Google si hace falta y después vuelve al equipo correcto.",
      "Si empiezas desde cero, pulsa Crear > Equipo, escribe el nombre y guarda. El primer usuario queda como admin.",
      "Cuando creas un equipo real, empieza limpio: sin jugadores, sin campos y sin partidos de demo.",
      "Comparte la invitación del equipo con los iconos de copiar o WhatsApp para que entren los demás.",
    ],
  },
  {
    audience: "Jugador",
    title: "Tu cuenta y tu ficha",
    intro: "Cada jugador registrado puede tener una ficha propia ligada a su usuario.",
    steps: [
      "Entra con Google y cambia tu nombre visible en el equipo, por ejemplo Alberto.",
      "Pulsa Crear > Ficha jugador para crear o editar tus datos: nombre, teléfono Bizum, foto, posición preferida y estado.",
      "Puedes añadir foto desde archivo o cámara; la app intenta centrar el avatar y puedes arrastrarlo dentro de la carta antes de guardar.",
      "Solo tú y los admins podéis editar tu ficha. Las valoraciones las hacen compañeros, no puedes votarte a ti mismo.",
    ],
  },
  {
    audience: "Admin",
    title: "Campos y ajustes iniciales",
    intro: "Antes de crear partidos conviene guardar los campos habituales y los ajustes básicos del sitio.",
    steps: [
      "Pulsa Crear > Campo para guardar un campo con nombre, precio y modalidad por defecto.",
      "La modalidad puede ser fútbol sala, fútbol 7 o fútbol 11.",
      "En Configurar puedes cambiar las instrucciones del equipo y los colores de los equipos.",
      "Los colores elegidos se aplican a bloques, listas, fichas, campo y goleadores.",
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
      "El turno de pago rota entre asistentes. El pagador aparece destacado con el icono del dólar.",
      "Cada jugador puede verse como pagado cuando se marque su dólar en verde.",
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
      "Ranking vivo se puede filtrar por la temporada guardada en cada partido, de septiembre a agosto, y ordenar por media, goles, partidos o ganados.",
      "Cada carta del ranking abre la ficha del jugador para consultar detalle, estado y evolución.",
    ],
  },
  {
    audience: "Jugador",
    title: "Valoraciones",
    intro: "La media del jugador sale de valoraciones por facetas, estilo ficha de fútbol.",
    steps: [
      "Las facetas son ritmo, tiro, pase, regate, defensa y físico. Los porteros tienen facetas específicas.",
      "La valoración se abre cuando ese jugador completa 3 partidos.",
      "Después de votar, tu voto queda cerrado hasta que ese jugador juegue otros 3 partidos.",
      "En el listado aparece si la valoración está abierta o cerrada, y la ficha muestra la evolución.",
    ],
  },
  {
    audience: "Todos",
    title: "Media, forma y equilibrio",
    intro: "La app separa la calidad real del jugador de su ritmo temporal para evitar castigos injustos.",
    steps: [
      "Media real = promedio de las facetas valoradas por compañeros. Si todavía no hay votos, se usa el valor base de la ficha.",
      "La media real no baja por no jugar, lesionarse o no apuntarse. Representa calidad: tiro, pase, defensa, físico o facetas de portero.",
      "Forma actual = porcentaje temporal calculado con los últimos 5 partidos jugados, la racha sin venir, lesiones y fiabilidad; no se muestra hasta que el jugador tenga al menos un partido finalizado.",
      "Nota reciente de partido = 6.2 más ajustes por victoria, derrota ajustada o amplia, goles, portería a cero y pocos o muchos goles encajados.",
      "Antes de tener partidos, la app usa una forma neutral interna del 100% solo para equilibrar, pero la ficha muestra Forma pendiente para no inventar un dato.",
      "Lesionado no castiga la media: marca el estado En recuperación y baja la forma de forma suave hasta que vuelva a jugar.",
      "Fiabilidad = 100% menos 7 puntos por cada cancelación tarde, con mínimo 70%. Afecta al equilibrio, no a la media.",
      "Valor para equilibrar = media real multiplicada por forma actual. Ejemplo: media 8.0 y forma 92% cuentan como 7.4 para montar equipos.",
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
    intro: "Cuando el equipo ya funciona, Configurar reúne permisos, estética, instrucciones y rescates.",
    steps: [
      "En Miembros puedes ver usuarios del equipo y cambiar su rol a Admin o Jugador.",
      "También puedes generar una invitación de admin para alguien que todavía no está registrado.",
      "Desde Configurar puedes crear una copia manual, ver las últimas copias del servidor y restaurar una copia si algo se ha borrado por error.",
      "La app crea copias automáticas al guardar o finalizar un partido, y también justo antes de borrar un equipo.",
      "El equipo se puede borrar con papelera y doble confirmación para evitar errores.",
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
