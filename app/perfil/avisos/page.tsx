import Link from "next/link";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";
import { NotificationPreferences } from "../../notification-preferences";

export default function NotificationPreferencesPage() {
  return (
    <OfficialProductShellV2
      active="perfil"
      context={{
        detail: "Canales y preferencias",
        eyebrow: "Perfil",
        status: "Servidor central",
        title: "Avisos",
      }}
    >
      <main className="notification-preferences-page official-ui-v2-notifications">
        <nav aria-label="Navegación de avisos">
          <Link href="/?mobile=perfil">Volver al perfil</Link>
        </nav>
        <NotificationPreferences />
      </main>
    </OfficialProductShellV2>
  );
}
