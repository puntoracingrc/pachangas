import Home from "../../../page";

export default async function AdminInvitationPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  return <Home entryRoute={{ adminInviteToken: token }} />;
}
