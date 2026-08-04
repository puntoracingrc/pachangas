import { Suspense } from "react";
import { MatchInvitationContent } from "../../../invitacion-partido/page";

export default async function MatchInvitationPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  return (
    <Suspense fallback={<main className="match-invitation-page"><section><p>Cargando invitación segura...</p></section></main>}>
      <MatchInvitationContent invitationToken={token} />
    </Suspense>
  );
}
