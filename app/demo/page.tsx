import { DemoWorldApp } from "../demo-world/demo-world-app";
import { currentDemoWorldManifest } from "../demo-world/current-demo-world-manifest";

export default function DemoWorldPage() {
  return <DemoWorldApp manifest={currentDemoWorldManifest()} mode="social" />;
}
