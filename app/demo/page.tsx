import manifestSource from "../../public/demo-world/v3-2/manifest.json";
import presentationSource from "../../public/demo-world/v3-3/manifest.json";
import fieldOperationsSource from "../../public/demo-world/v3-4/manifest.json";
import { DemoWorldApp } from "../demo-world/demo-world-app";
import type { DemoWorldV32Manifest } from "../demo-world/demo-world-v3-2-contract";
import type { DemoWorldV33PresentationManifest } from "../demo-world/demo-world-v3-3-contract";
import type { DemoWorldV34Manifest, DemoWorldV34PresentationManifest } from "../demo-world/demo-world-v3-4-contract";

export default function DemoWorldPage() {
  const authority = manifestSource as DemoWorldV32Manifest;
  const manifest: DemoWorldV34Manifest = {
    ...authority,
    fieldOperations: fieldOperationsSource as DemoWorldV34PresentationManifest,
    presentation: presentationSource as DemoWorldV33PresentationManifest,
    version: 3.4,
  };
  return <DemoWorldApp manifest={manifest} />;
}
