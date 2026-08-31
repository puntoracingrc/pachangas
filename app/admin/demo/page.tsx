import { notFound } from "next/navigation";
import { DemoWorldApp } from "../../demo-world/demo-world-app";
import { currentDemoWorldManifest } from "../../demo-world/current-demo-world-manifest";
import { requirePlatformPage } from "../_lib/platform-auth";

export default async function PlatformDemoWorldPage() {
  const session = await requirePlatformPage("overview.read");
  if (session.access.role !== "platform_owner") notFound();
  return <DemoWorldApp manifest={currentDemoWorldManifest()} mode="full" />;
}
