const manualSections = [
  {
    title: "Equipo privado",
    body: "Crea un grupo, comparte la invitación y gestiona miembros. Los admins pueden crear partidos, campos, jugadores, cerrar alineaciones y borrar errores.",
  },
  {
    title: "Próximos partidos",
    body: "Lista los partidos abiertos. El orden de Voy decide titulares, reservas y espera. Si alguien se baja, el primer reserva sube automáticamente.",
  },
  {
    title: "Partido",
    body: "Configura campo, fecha, modalidad, precio y reservas. El pago rota entre asistentes y puedes marcar quién ha pagado.",
  },
  {
    title: "Alineaciones",
    body: "El sistema separa porteros, coloca fichas en el campo y permite equipos aleatorios o equilibrados por estadísticas. El admin puede cerrar o reabrir la alineación.",
  },
  {
    title: "Ficha jugador",
    body: "Guarda foto, teléfono Bizum, posición preferida, portero fijo, lesión, goles y valoraciones tipo FIFA por facetas.",
  },
  {
    title: "Valoraciones",
    body: "Se abren cada 3 partidos jugados por jugador. Al votar se cierran para ti hasta que ese jugador complete otros 3 partidos.",
  },
  {
    title: "Resultado e historial",
    body: "Rellena marcador, asigna goleadores sin superar el resultado y finaliza el partido para archivarlo en histórico y actualizar ranking.",
  },
  {
    title: "Ranking vivo",
    body: "Ordena jugadores por rendimiento, goles y victorias. Cada fila abre la ficha para consultar detalle, evolución y estado.",
  },
];

export function ManualContent() {
  return (
    <div className="manual-grid">
      {manualSections.map((section) => (
        <article key={section.title}>
          <b>{section.title}</b>
          <p>{section.body}</p>
        </article>
      ))}
    </div>
  );
}
