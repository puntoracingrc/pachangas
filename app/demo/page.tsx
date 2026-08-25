import manifestSource from "../../public/demo-world/v2/manifest.json";
import { DemoWorldApp } from "../demo-world/demo-world-app";
import type { DemoWorldV2Manifest } from "../demo-world/demo-world-v2-contract";

export default function DemoWorldPage() {
  return <DemoWorldApp manifest={manifestSource as DemoWorldV2Manifest} />;
}
