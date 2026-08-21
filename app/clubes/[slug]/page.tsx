import { PublicClubProfile } from "./public-club-profile";

export default async function PublicClubPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return <PublicClubProfile slug={slug} />;
}
