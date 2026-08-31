import manifestSource from "../../public/demo-world/v3-2/manifest.json";
import presentationSource from "../../public/demo-world/v3-3/manifest.json";
import fieldOperationsSource from "../../public/demo-world/v3-4/manifest.json";
import seasonFieldAllocationSource from "../../public/demo-world/v3-5/manifest.json";
import type { DemoWorldV32Manifest } from "./demo-world-v3-2-contract";
import type { DemoWorldV33PresentationManifest } from "./demo-world-v3-3-contract";
import type { DemoWorldV34PresentationManifest } from "./demo-world-v3-4-contract";
import type { DemoWorldV35Manifest, DemoWorldV35PresentationManifest } from "./demo-world-v3-5-contract";

export function currentDemoWorldManifest(): DemoWorldV35Manifest {
  const authority = manifestSource as DemoWorldV32Manifest;
  return {
    ...authority,
    fieldOperations: fieldOperationsSource as DemoWorldV34PresentationManifest,
    presentation: presentationSource as DemoWorldV33PresentationManifest,
    seasonFieldAllocation: seasonFieldAllocationSource as DemoWorldV35PresentationManifest,
    version: 3.5,
  };
}
