import Link from "next/link";
import type { ReactNode } from "react";

export const legalInfo = {
  appName: "Pachangas IQ",
  domain: "pachangasiq.com",
  owner: "Titular de Pachangas IQ",
  ownerStatus: "Datos legales del responsable pendientes de completar por el titular",
  taxId: "Pendiente de completar",
  address: "Pendiente de completar",
  contactEmail: "Pendiente de completar",
  lastUpdated: "29 de julio de 2026",
};

export const legalLinks = [
  { href: "/aviso-legal", label: "Aviso legal" },
  { href: "/privacidad", label: "Privacidad" },
  { href: "/cookies", label: "Cookies" },
  { href: "/condiciones", label: "Condiciones" },
  { href: "/condiciones-venta", label: "Condiciones de venta" },
];

type LegalSection = {
  title: string;
  body?: ReactNode;
  items?: ReactNode[];
};

export type LegalPageContent = {
  title: string;
  eyebrow: string;
  intro: string;
  sections: LegalSection[];
};

export const legalPages: Record<string, LegalPageContent> = {
  avisoLegal: {
    eyebrow: "Información del titular",
    title: "Aviso legal",
    intro:
      "Información general del servicio Pachangas IQ y del responsable de la web. Estos datos deben completarse con la identidad real del titular antes de una explotación comercial estable.",
    sections: [
      {
        title: "Responsable del sitio",
        items: [
          <><strong>Nombre comercial:</strong> {legalInfo.appName}</>,
          <><strong>Dominio:</strong> {legalInfo.domain}</>,
          <><strong>Responsable:</strong> {legalInfo.owner}</>,
          <><strong>Estado:</strong> {legalInfo.ownerStatus}</>,
          <><strong>NIF/CIF:</strong> {legalInfo.taxId}</>,
          <><strong>Domicilio:</strong> {legalInfo.address}</>,
          <><strong>Contacto:</strong> {legalInfo.contactEmail}</>,
        ],
      },
      {
        title: "Actividad",
        body:
          "Pachangas IQ es una aplicación web para organizar grupos privados de pachangas: creación de partidos, asistencia, reservas, reparto de pago del campo, fichas de jugadores, valoraciones, rankings, historial y suscripción del owner del grupo.",
      },
      {
        title: "Acceso y uso",
        items: [
          "El acceso a grupos reales requiere invitación o creación de grupo por un usuario registrado.",
          "Las funciones de administración, creación de partidos, campos, roles y suscripción están reservadas a owner o admins según corresponda.",
          "El usuario se compromete a usar la web de forma lícita, respetuosa y sin publicar datos, fotos o contenido de terceros sin permiso.",
          "Las funciones públicas de mercado de fichajes, cuando se activen, deberán configurarse como opt-in y con información visible para el jugador.",
        ],
      },
      {
        title: "Propiedad intelectual",
        body:
          "El diseño, marca, textos, código, iconos y elementos propios de Pachangas IQ pertenecen a su titular o se usan con licencia. Las fotos, nombres y datos introducidos por usuarios pertenecen a sus respectivos titulares y se usan para prestar el servicio.",
      },
      {
        title: "Responsabilidad",
        body:
          "Pachangas IQ facilita la organización de partidos, pero no participa en reservas de instalaciones, cobros entre jugadores, Bizums, asistencia física al partido, lesiones, incidencias deportivas ni acuerdos privados entre usuarios.",
      },
      {
        title: "Normativa de referencia",
        items: [
          <a href="https://www.boe.es/buscar/act.php?id=BOE-A-2002-13758" rel="noreferrer" target="_blank">Ley 34/2002 de servicios de la sociedad de la información y comercio electrónico</a>,
          <a href="https://www.boe.es/buscar/act.php?id=BOE-A-2018-16673" rel="noreferrer" target="_blank">Ley Orgánica 3/2018 de protección de datos personales y garantía de derechos digitales</a>,
        ],
      },
    ],
  },
  privacidad: {
    eyebrow: "Datos personales",
    title: "Política de privacidad",
    intro:
      "Esta política explica qué datos trata Pachangas IQ para crear grupos, fichas, partidos, rankings, pagos de suscripción y futuras funciones sociales como el mercado de fichajes.",
    sections: [
      {
        title: "Responsable",
        body:
          `${legalInfo.owner}. ${legalInfo.ownerStatus}. Contacto: ${legalInfo.contactEmail}.`,
      },
      {
        title: "Datos que podemos tratar",
        items: [
          "Cuenta de acceso: identificador de usuario, nombre, email y datos básicos recibidos mediante Google OAuth.",
          "Datos de grupo: grupo de pachangas, roles, invitaciones, campos, direcciones verificadas de instalaciones deportivas, coordenadas del campo para previsión meteorológica, partidos, alineaciones, reservas, pagos marcados y configuración.",
          "Ficha de jugador: nombre visible, foto, encuadre, teléfono Bizum, fecha de nacimiento, edad calculada, posición, portero fijo, lesión, estadísticas, valoraciones, media, forma, goles y asistencia.",
          "Datos de pago del owner: información necesaria para activar, renovar, cancelar o comprobar planes de Stripe. Pachangas IQ no almacena los datos completos de tarjeta.",
          "Datos técnicos: logs de seguridad, errores, IP aproximada, navegador, dispositivo, tokens de sesión y datos estrictamente necesarios para sincronización.",
          "Datos opcionales futuros: disponibilidad por zona, perfil público de mercado de fichajes, invitaciones puntuales, mensajes relacionados con partidos y filtros de proximidad respecto a campos deportivos.",
        ],
      },
      {
        title: "Finalidades",
        items: [
          "Crear y mantener grupos privados de pachangas.",
          "Gestionar asistencia, reservas, alineaciones, pagos del campo y fotos del partido.",
          "Mostrar fichas, rankings, medias, forma y evolución dentro de cada grupo.",
          "Permitir acceso con Google, validar campos deportivos con Google Maps Platform, mostrar la previsión del tiempo del partido con Google Weather, sincronización en Supabase y despliegue del servicio en Vercel.",
          "Gestionar suscripciones del owner, facturación técnica y eventos de pago mediante Stripe.",
          "Prevenir abuso, errores de sincronización, accesos no autorizados y pérdida accidental de datos.",
          "Si el usuario lo activa, mostrar su ficha pública en un mercado de fichajes por zona.",
        ],
      },
      {
        title: "Base jurídica",
        items: [
          "Ejecución del servicio solicitado por el usuario: cuenta, grupo, fichas, partidos, sincronización y acceso.",
          "Consentimiento: fotos, perfil público, mercado de fichajes, comunicaciones no esenciales y datos opcionales.",
          "Interés legítimo: seguridad, prevención de abuso, copias de rescate, mejora de estabilidad y resolución de incidencias.",
          "Obligación legal: conservación de datos necesarios para obligaciones fiscales, contables o reclamaciones cuando existan pagos.",
        ],
      },
      {
        title: "Proveedores",
        items: [
          "Supabase: base de datos, autenticación, almacenamiento y sincronización.",
          "Vercel: alojamiento, despliegue, entrega de la web y logs técnicos.",
          "Google: autenticación OAuth cuando el usuario elige iniciar sesión con Google.",
          "Google Maps Platform: sugerencias y validación de direcciones de campos mediante Places cuando se crea una instalación deportiva.",
          "Google Weather: previsión meteorológica aproximada durante el partido usando únicamente la ubicación del campo.",
          "Stripe: pagos, suscripciones, portal de cliente y eventos de facturación.",
          "WhatsApp: al pulsar compartir se abre una aplicación externa; WhatsApp trata esos datos bajo sus propias condiciones.",
        ],
      },
      {
        title: "Conservación",
        body:
          "Los datos se conservan mientras exista la cuenta, el grupo o una obligación legal aplicable. El histórico deportivo puede mantenerse para preservar ranking y resultados del grupo, incluso si una ficha se marca como inactiva, salvo que proceda su supresión o anonimización.",
      },
      {
        title: "Derechos",
        body:
          "Puedes solicitar acceso, rectificación, supresión, oposición, limitación, portabilidad o retirada del consentimiento escribiendo al contacto indicado. También puedes reclamar ante la Agencia Española de Protección de Datos si consideras que el tratamiento no es correcto.",
      },
      {
        title: "Menores",
        body:
          "La web no está pensada para menores de 14 años. Las funciones públicas, de mercado de fichajes, pago o contacto con personas fuera del grupo deberán usarse solo por mayores de edad o con las garantías y autorizaciones necesarias.",
      },
      {
        title: "Normativa de referencia",
        items: [
          <a href="https://www.aepd.es/guias/guia-modelo-clausula-informativa.pdf" rel="noreferrer" target="_blank">Guía AEPD sobre cláusulas informativas</a>,
          <a href="https://www.aepd.es/preguntas-frecuentes/10-menores-y-educacion/FAQ-1001-cual-es-la-edad-para-que-los-menores-puedan-prestar-consentimiento-para-tratar-sus-datos-personales" rel="noreferrer" target="_blank">AEPD: consentimiento de menores</a>,
        ],
      },
    ],
  },
  cookies: {
    eyebrow: "Almacenamiento técnico",
    title: "Política de cookies",
    intro:
      "Pachangas IQ usa almacenamiento técnico necesario para iniciar sesión, mantener la sesión, recordar preferencias y sincronizar la aplicación. No se han añadido cookies publicitarias ni analítica de marketing en esta versión.",
    sections: [
      {
        title: "Qué usamos ahora",
        items: [
          "Datos técnicos de sesión de Supabase para mantener el acceso del usuario.",
          "Valores temporales de seguridad del login con Google, como nonce y URL de retorno.",
          "Preferencias locales de interfaz y estado de la app necesarios para que el producto funcione.",
          "Cookies o almacenamiento estrictamente necesarios de Vercel, Supabase, Google, Google Maps Platform o Stripe cuando intervienen en autenticación, seguridad, validación de campos o pago.",
        ],
      },
      {
        title: "Cookies no necesarias",
        body:
          "No usamos cookies de publicidad, remarketing ni analítica no esencial en esta versión. Si más adelante se añade analítica, medición avanzada o marketing, se mostrará un panel de consentimiento para aceptar, rechazar o configurar.",
      },
      {
        title: "Cómo gestionarlas",
        body:
          "Puedes borrar o bloquear cookies desde la configuración de tu navegador. Si bloqueas almacenamiento técnico, el login, las invitaciones o la sincronización pueden dejar de funcionar correctamente.",
      },
      {
        title: "Normativa de referencia",
        items: [
          <a href="https://www.aepd.es/guias/guia-cookies.pdf" rel="noreferrer" target="_blank">Guía sobre el uso de cookies de la AEPD</a>,
        ],
      },
    ],
  },
  condiciones: {
    eyebrow: "Normas del servicio",
    title: "Condiciones de uso",
    intro:
      "Estas condiciones regulan el uso de Pachangas IQ por jugadores, admins y owners de grupos de pachangas.",
    sections: [
      {
        title: "Roles",
        items: [
          "Owner: crea el grupo, gestiona la suscripción, puede nombrar o quitar admins y borrar el grupo.",
          "Admin: puede crear y configurar partidos, campos, jugadores, alineaciones, resultados, fotos y copias, según permisos activos.",
          "Jugador: puede gestionar su ficha, responder asistencia, marcar pagos propios y participar en valoraciones cuando estén abiertas.",
        ],
      },
      {
        title: "Grupos, invitaciones y partidos",
        items: [
          "Cada grupo funciona como un espacio privado con su propio historial, fichas y rankings.",
          "Un enlace de invitación permite entrar al grupo o a un partido concreto, según el caso.",
          "Los partidos en borrador no aceptan asistencia hasta que el admin los guarda.",
          "Finalizar un partido archiva el resultado y puede actualizar goles, ranking, forma y estadísticas.",
        ],
      },
      {
        title: "Fichas y valoraciones",
        items: [
          "Cada jugador puede editar su propia ficha; los admins pueden corregir fichas del grupo.",
          "No puedes votar tu propia ficha.",
          "Las valoraciones y estadísticas deben reflejar el uso normal del grupo y no manipularse para perjudicar a otros.",
          "Si importas una ficha a otro grupo, se copia una base inicial, pero el historial de ese grupo empieza separado.",
        ],
      },
      {
        title: "Contenido de usuarios",
        body:
          "Al subir fotos, nombres, comentarios o datos confirmas que tienes derecho a hacerlo y autorizas su uso dentro de Pachangas IQ para prestar el servicio. No publiques contenido ofensivo, ilegal, discriminatorio, íntimo, no consentido o que vulnere derechos de terceros.",
      },
      {
        title: "Mercado de fichajes",
        body:
          "Cuando se active, el mercado de fichajes será voluntario. Un jugador podrá publicar una ficha visible por zona y aceptar o rechazar invitaciones a partidos. La búsqueda podrá usar la ubicación verificada del campo y la disponibilidad indicada por el jugador. Aceptar un partido no implica entrar al grupo completo salvo invitación posterior.",
      },
      {
        title: "Limitaciones",
        body:
          "Pachangas IQ puede evolucionar, cambiar funciones, suspender cuentas por abuso, corregir errores o limitar usos que comprometan seguridad, privacidad o estabilidad del servicio.",
      },
    ],
  },
  condicionesVenta: {
    eyebrow: "Pagos y suscripciones",
    title: "Condiciones de contratación",
    intro:
      "Pachangas IQ incluye funciones de pago para owners de grupos. El resto de jugadores puede usar el grupo sin contratar una suscripción propia.",
    sections: [
      {
        title: "Planes",
        items: [
          "Prueba gratuita: cada grupo puede finalizar 2 partidos sin suscripción.",
          "Plan mensual: 5,99 € al mes.",
          "Plan anual: 64,99 € al año.",
          "Los precios definitivos, impuestos aplicables y moneda se muestran en Stripe antes de confirmar el pago.",
        ],
      },
      {
        title: "Quién paga",
        body:
          "La suscripción corresponde al owner del grupo. Los jugadores y admins no pagan una suscripción individual por usar un grupo ya activo. Si el grupo decide repartir el coste por Bizum, ese reparto es un acuerdo privado entre miembros y no un cobro gestionado por Pachangas IQ.",
      },
      {
        title: "Renovación y cancelación",
        body:
          "Los planes se renuevan automáticamente por el periodo contratado hasta que el owner los cancele desde el portal de Stripe o el sistema habilitado. La cancelación evita renovaciones futuras y el acceso de pago se mantiene hasta el final del periodo ya abonado, salvo que la ley o Stripe indiquen otra cosa.",
      },
      {
        title: "Pago seguro",
        body:
          "Los pagos se procesan mediante Stripe. Pachangas IQ no guarda los datos completos de tarjeta. Stripe puede aplicar sus propios controles antifraude, autenticación reforzada y políticas de seguridad.",
      },
      {
        title: "Desistimiento y reembolsos",
        body:
          "Cuando proceda legalmente, el consumidor puede tener derecho de desistimiento en contratación a distancia. En servicios digitales que empiezan a prestarse inmediatamente, ese derecho puede limitarse si el usuario acepta expresamente el inicio del servicio y reconoce la pérdida del desistimiento. Cualquier solicitud se revisará según la normativa aplicable y las condiciones aceptadas en el momento de contratar.",
      },
      {
        title: "Suspensión por falta de pago",
        body:
          "Si una suscripción queda impagada, cancelada o vencida tras la prueba gratuita, el grupo puede conservar sus datos, pero la creación o finalización de nuevos partidos puede quedar limitada hasta reactivar el plan.",
      },
      {
        title: "Normativa de referencia",
        items: [
          <a href="https://www.boe.es/buscar/act.php?id=BOE-A-2007-20555" rel="noreferrer" target="_blank">Texto refundido de la Ley General para la Defensa de los Consumidores y Usuarios</a>,
          <a href="https://portal-cec.consumo.gob.es/es/informacion-general/compras-online/derechos-del-consumidor" rel="noreferrer" target="_blank">Centro Europeo del Consumidor: derechos en compras online</a>,
        ],
      },
    ],
  },
};

export function LegalFooter() {
  return (
    <footer className="legal-footer">
      <div>
        <strong>{legalInfo.appName}</strong>
        <span>Organización de grupos de pachangas con funciones de suscripción para owners.</span>
      </div>
      <nav aria-label="Enlaces legales">
        {legalLinks.map((link) => (
          <Link key={link.href} href={link.href}>
            {link.label}
          </Link>
        ))}
      </nav>
    </footer>
  );
}

export function LegalPage({ page }: { page: LegalPageContent }) {
  return (
    <main className="legal-page">
      <section className="manual-hero legal-hero">
        <div>
          <p className="eyebrow">{page.eyebrow}</p>
          <h1>{page.title}</h1>
          <p className="hero-copy">{page.intro}</p>
          <small>Última actualización: {legalInfo.lastUpdated}</small>
        </div>
        <Link className="secondary-button manual-back-button" href="/">
          Volver
        </Link>
      </section>

      <section className="top-panel legal-page-panel">
        <div className="legal-warning">
          <strong>Datos del titular pendientes</strong>
          <p>
            Este texto deja preparada la estructura legal de la web. Antes de explotación comercial estable hay que completar responsable, NIF/CIF, domicilio y correo de contacto reales.
          </p>
        </div>
        {page.sections.map((section) => (
          <article key={section.title} className="legal-section">
            <h2>{section.title}</h2>
            {section.body ? <p>{section.body}</p> : null}
            {section.items ? (
              <ul>
                {section.items.map((item, index) => (
                  <li key={`${section.title}-${index}`}>{item}</li>
                ))}
              </ul>
            ) : null}
          </article>
        ))}
      </section>
    </main>
  );
}
