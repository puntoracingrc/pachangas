import manifestSource from "../../public/demo-world/v3-2/manifest.json";
import presentationSource from "../../public/demo-world/v3-3/manifest.json";
import { DemoWorldApp } from "../demo-world/demo-world-app";
import type { DemoWorldV32Manifest } from "../demo-world/demo-world-v3-2-contract";
import type { DemoWorldV33Manifest, DemoWorldV33PresentationManifest } from "../demo-world/demo-world-v3-3-contract";

export default function DemoWorldPage() {
  const authority = manifestSource as DemoWorldV32Manifest;
  const manifest: DemoWorldV33Manifest = {
    ...authority,
    presentation: presentationSource as DemoWorldV33PresentationManifest,
    version: 3.3,
  };
  return <DemoWorldApp manifest={manifest} />;
}
