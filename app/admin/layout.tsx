import type { Metadata } from "next";
import { AdminSessionBootstrap } from "./_components/admin-session-bootstrap";
import { PlatformShell } from "./_components/platform-shell";
import { platformAccessFromCookies } from "./_lib/platform-auth";
import { currentPlatformEnvironment } from "./_lib/platform-contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export const metadata: Metadata = {
  title: "Control Center | Pachangas IQ",
  robots: { follow: false, index: false },
};

export default async function PlatformAdminLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const session = await platformAccessFromCookies();
  if (!session) return <AdminSessionBootstrap />;
  return (
    <PlatformShell access={session.access} environment={currentPlatformEnvironment()}>
      {children}
    </PlatformShell>
  );
}
