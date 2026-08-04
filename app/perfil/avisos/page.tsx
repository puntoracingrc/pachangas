import Link from "next/link";
import { NotificationPreferences } from "../../notification-preferences";

export default function NotificationPreferencesPage() {
  return (
    <main className="notification-preferences-page">
      <nav aria-label="Navegación de avisos">
        <Link href="/?mobile=perfil">Volver al perfil</Link>
      </nav>
      <NotificationPreferences />
    </main>
  );
}
