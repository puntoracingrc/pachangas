"use client";

export type MobileAppTab = "inicio" | "partido" | "mercado" | "equipo" | "perfil";

type MobileAppNavProps = {
  active: MobileAppTab;
  links?: Partial<Record<MobileAppTab, string>>;
  onNavigate?: (tab: MobileAppTab) => void;
};

const items: Array<{ id: MobileAppTab; label: string }> = [
  { id: "inicio", label: "Inicio" },
  { id: "partido", label: "Partido" },
  { id: "mercado", label: "Mercado" },
  { id: "equipo", label: "Equipo" },
  { id: "perfil", label: "Perfil" },
];

function MobileNavIcon({ name }: { name: MobileAppTab }) {
  if (name === "inicio") {
    return (
      <svg aria-hidden="true" viewBox="0 0 24 24">
        <path d="M3.5 10.5 12 3l8.5 7.5v9a1.5 1.5 0 0 1-1.5 1.5h-4.5v-6h-5v6H5a1.5 1.5 0 0 1-1.5-1.5z" />
      </svg>
    );
  }

  if (name === "partido") {
    return (
      <svg aria-hidden="true" viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="9" />
        <path d="m9.5 8 2.5-1.7L14.5 8l-.9 3h-3.2zM6.3 12.2l4.1-1.2M17.7 12.2 13.6 11M8.5 18l1.9-7M15.5 18l-1.9-7" />
      </svg>
    );
  }

  if (name === "mercado") {
    return (
      <svg aria-hidden="true" viewBox="0 0 24 24">
        <circle cx="9" cy="8" r="3" />
        <path d="M3.8 19c.5-4 2.3-6 5.2-6s4.7 2 5.2 6M16.5 8.5h4M18.5 6.5v4M16 15.5h5M18.5 13v5" />
      </svg>
    );
  }

  if (name === "equipo") {
    return (
      <svg aria-hidden="true" viewBox="0 0 24 24">
        <circle cx="8" cy="8" r="3" />
        <circle cx="17" cy="9" r="2.5" />
        <path d="M2.5 20c.4-4.2 2.2-6.5 5.5-6.5s5.1 2.3 5.5 6.5M14 14.2c.8-.5 1.8-.7 3-.7 2.8 0 4.2 2.1 4.5 5.5" />
      </svg>
    );
  }

  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <circle cx="12" cy="8" r="4" />
      <path d="M4.5 21c.4-5.2 2.9-8 7.5-8s7.1 2.8 7.5 8" />
    </svg>
  );
}

export function MobileAppNav({ active, links = {}, onNavigate }: MobileAppNavProps) {
  return (
    <nav className="mobile-app-nav" aria-label="Navegación principal móvil">
      <div className="mobile-app-nav-inner">
        {items.map((item) => {
          const selected = active === item.id;
          const content = (
            <>
              <span className="mobile-app-nav-icon">
                <MobileNavIcon name={item.id} />
              </span>
              <span>{item.label}</span>
            </>
          );
          const className = selected ? "mobile-app-nav-item active" : "mobile-app-nav-item";

          if (links[item.id]) {
            return (
              <a className={className} href={links[item.id]} key={item.id} aria-current={selected ? "page" : undefined}>
                {content}
              </a>
            );
          }

          return (
            <button
              className={className}
              key={item.id}
              type="button"
              aria-current={selected ? "page" : undefined}
              onClick={() => onNavigate?.(item.id)}
            >
              {content}
            </button>
          );
        })}
      </div>
    </nav>
  );
}
