import manifestSource from "../../public/demo-world/v3-2/manifest.json";
import { DemoWorldApp } from "../demo-world/demo-world-app";
import type { DemoWorldV32Manifest } from "../demo-world/demo-world-v3-2-contract";

export default function DemoWorldPage() {
  return <DemoWorldApp manifest={manifestSource as DemoWorldV32Manifest} />;
}
