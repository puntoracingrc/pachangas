import { PublicRefereeProfile } from "./public-referee-profile";

export default async function RefereePublicPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return <PublicRefereeProfile slug={slug} />;
}
