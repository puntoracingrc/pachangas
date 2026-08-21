import manifestSource from "../../public/demo-world/v1/manifest.json";
import type { DemoWorldManifest } from "../demo-world/demo-world-contract";
import { DemoWorldApp } from "../demo-world/demo-world-app";

export default function DemoWorldPage() {
  return <DemoWorldApp manifest={manifestSource as DemoWorldManifest} />;
}
