import { notFound } from "next/navigation";
import { syntheticWorldAdminEnabled } from "../../../simulation/synthetic-world/src/environment";
import { SyntheticWorldStore } from "../../../simulation/synthetic-world/src/store";
import { requirePlatformPage } from "../_lib/platform-auth";
import { SimulationWorldDashboard } from "./simulation-world-dashboard";

export const dynamic = "force-dynamic";

export default async function SimulationWorldPage({
  searchParams,
}: {
  searchParams: Promise<{ world?: string }>;
}) {
  if (!syntheticWorldAdminEnabled()) notFound();
  await requirePlatformPage("labs.read");
  const store = new SyntheticWorldStore();
  const worlds = await store.listWorlds();
  const requested = (await searchParams).world;
  const selected = requested ? worlds.find(({ id }) => id === requested) : worlds[0];
  const orderedWorlds = selected ? [selected, ...worlds.filter(({ id }) => id !== selected.id)] : worlds;
  return <SimulationWorldDashboard initialData={null} initialWorlds={orderedWorlds} />;
}
