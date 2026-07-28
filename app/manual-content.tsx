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
    audience: "Jugador",
    title: "Tu cuenta y tu ficha",
    intro: "Cada jugador registrado puede tener una ficha propia ligada a su usuario.",
    steps: [
      "Entra con Google y cambia tu nombre visible en el equipo, por ejemplo Alberto.",
      "Abre Mi ficha para crear o editar tus datos: nombre, teléfono Bizum, foto, posición preferida y estado.",
      "Puedes añadir foto desde archivo o cámara; la app intenta centrar el avatar para que encaje mejor.",
      "Solo tú y los admins podéis editar tu ficha. Las valoraciones las hacen compañeros, no puedes votarte a ti mismo.",
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
    audience: "Jugador",
    title: "Valoraciones",
    intro: "La media del jugador sale de valoraciones por facetas, estilo ficha de fútbol.",
    steps: [
      "Las facetas son ritmo, tiro, pase, regate, defensa y físico.",
      "La valoración se abre cuando ese jugador completa 3 partidos.",
      "Después de votar, tu voto queda cerrado hasta que ese jugador juegue otros 3 partidos.",
      "En el listado aparece si la valoración está abierta o cerrada, y la ficha muestra la evolución.",
    ],
  },
  {
    audience: "Admin",
    title: "Crear y configurar equipo",
    intro: "El primer usuario que crea el equipo queda como admin y puede dar permisos a otros.",
    steps: [
      "Pulsa + Equipo, escribe el nombre y guarda. El equipo se crea vacío.",
      "Comparte la invitación con los iconos de copiar o WhatsApp.",
      "En Miembros puedes ver usuarios del equipo y cambiar su rol a Admin o Jugador.",
      "También puedes generar una invitación de admin para alguien que todavía no está registrado.",
      "El equipo se puede borrar con papelera y doble confirmación para evitar errores.",
    ],
  },
  {
    audience: "Admin",
    title: "Campos y configuración",
    intro: "Antes de crear partidos conviene guardar los campos habituales y los ajustes del sitio.",
    steps: [
      "Con + Campo creas un campo con nombre, precio y modalidad por defecto.",
      "La modalidad puede ser fútbol sala, fútbol 7 o fútbol 11.",
      "En Configurar puedes cambiar nombre de la web, título, subtítulo y colores de los equipos.",
      "Los colores elegidos se aplican a bloques, listas, fichas, campo y goleadores.",
    ],
  },
  {
    audience: "Admin",
    title: "Crear partido",
    intro: "Un partido nuevo nace como borrador para evitar que la gente se apunte antes de estar bien configurado.",
    steps: [
      "Pulsa + Partido y revisa campo, fecha, modalidad, precio y reservas.",
      "Mientras no pulses Guardar partido, no aparece en Próximos partidos y nadie puede marcar asistencia.",
      "Al guardar se activan confirmaciones, compartir, alineación, resultado y pago.",
      "El enlace del partido se comparte con Copiar link o WhatsApp.",
      "Si te equivocas o el partido no se juega, puedes borrarlo con papelera y doble confirmación.",
    ],
  },
  {
    audience: "Admin",
    title: "Alineaciones",
    intro: "La app propone equipos y coloca fichas en el campo según modalidad y posiciones.",
    steps: [
      "Los porteros fijos se separan en equipos diferentes cuando hay dos disponibles.",
      "Puedes mover jugadores manualmente de un equipo a otro con las flechas.",
      "Aleatorio reparte al azar; Equilibrado por stats intenta compensar medias y posiciones.",
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
      "Cualquier miembro puede subir una foto de equipo como recuerdo; solo un admin puede quitarla.",
      "Al pulsar Finalizar partido, el partido pasa al historial.",
      "Después de finalizar, campo, fecha, modalidad, precio y reservas quedan bloqueados.",
      "Si hubo un error, aún puedes corregir asistencia y goleadores para ajustar el histórico.",
    ],
  },
  {
    audience: "Admin",
    title: "Jugadores",
    intro: "Los admins pueden crear fichas y mantener limpia la plantilla.",
    steps: [
      "Con + Jugador creas una ficha básica cuando alguien todavía no se ha registrado.",
      "Un jugador registrado puede reclamar o crear su propia ficha.",
      "Portero fijo ayuda a que el sistema lo coloque siempre en portería.",
      "Lesionado bloquea el Voy y muestra el icono de hospital en listados.",
      "Borrar jugador lo deja fuera del grupo, pero no elimina su histórico ni su ranking pasado.",
    ],
  },
  {
    audience: "Todos",
    title: "Historial y ranking",
    intro: "La memoria del grupo vive en los partidos cerrados, el ranking y las fichas.",
    steps: [
      "Próximos partidos muestra solo partidos abiertos y guardados.",
      "Historial muestra los últimos partidos con separadores por mes, foto en miniatura y resumen de pago y goles.",
      "Ranking vivo se puede filtrar por temporada y ordenar por media, goles, partidos o ganados.",
      "Cada fila del ranking abre la ficha del jugador para consultar detalle, estado y evolución.",
    ],
  },
];

export function ManualContent() {
  return (
    <div className="manual-flow-list">
      {manualFlows.map((flow) => (
        <article key={flow.title} className="manual-flow-card">
          <div>
            <span>{flow.audience}</span>
            <b>{flow.title}</b>
          </div>
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
