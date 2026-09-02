import Link from "next/link";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";
import { NotificationPreferences } from "../../notification-preferences";

export default function NotificationSettingsPage() {
  return (
    <OfficialProductShellV2
      active="perfil"
      context={{ detail: "Canales y preferencias", eyebrow: "Ajustes", status: "Servidor central", title: "Notificaciones", type: "profile" }}
    >
      <main className="notification-preferences-page official-ui-v2-notifications">
        <nav aria-label="Navegación de notificaciones"><Link href="/avisos">Volver a Avisos</Link></nav>
        <NotificationPreferences />
      </main>
    </OfficialProductShellV2>
  );
}
