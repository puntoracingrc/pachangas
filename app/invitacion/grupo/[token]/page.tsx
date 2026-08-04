import Home from "../../../page";

export default async function GroupInvitationPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  return <Home entryRoute={{ inviteToken: token }} />;
}
