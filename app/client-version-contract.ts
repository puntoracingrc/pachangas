export const CLIENT_UPDATE_REQUIRED = "CLIENT_UPDATE_REQUIRED";
export const INITIAL_MINIMUM_SUPPORTED_CLIENT_VERSION = "1.0.0";
export const V1_UNVERSIONED = "v1-unversioned";

export type ClientVersionClassification = typeof V1_UNVERSIONED | string;
export type ClientDisplayMode = "browser" | "fullscreen" | "standalone";

type ParsedSemVer = {
  core: [string, string, string];
  prerelease: string[];
};

const semVerPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/;

export const CLIENT_VERSION = classifyClientVersion(process.env.NEXT_PUBLIC_PACHANGAS_CLIENT_VERSION);
export const SERVICE_WORKER_VERSION = classifyClientVersion(process.env.NEXT_PUBLIC_PACHANGAS_SERVICE_WORKER_VERSION);

function compareNumericIdentifiers(left: string, right: string) {
  if (left.length !== right.length) return left.length < right.length ? -1 : 1;
  if (left === right) return 0;
  return left < right ? -1 : 1;
}

export function parseSemVer(value: string): ParsedSemVer | null {
  const match = semVerPattern.exec(value.trim());
  if (!match) return null;

  const prerelease = match[4]?.split(".") ?? [];
  if (prerelease.some((identifier) => /^\d+$/.test(identifier) && identifier.length > 1 && identifier.startsWith("0"))) {
    return null;
  }

  return {
    core: [match[1], match[2], match[3]],
    prerelease,
  };
}

export function compareSemVer(left: string, right: string) {
  const parsedLeft = parseSemVer(left);
  const parsedRight = parseSemVer(right);
  if (!parsedLeft || !parsedRight) throw new Error(`Invalid SemVer comparison: ${left} / ${right}`);

  for (let index = 0; index < parsedLeft.core.length; index += 1) {
    const comparison = compareNumericIdentifiers(parsedLeft.core[index], parsedRight.core[index]);
    if (comparison !== 0) return comparison;
  }

  if (parsedLeft.prerelease.length === 0 && parsedRight.prerelease.length === 0) return 0;
  if (parsedLeft.prerelease.length === 0) return 1;
  if (parsedRight.prerelease.length === 0) return -1;

  const prereleaseLength = Math.max(parsedLeft.prerelease.length, parsedRight.prerelease.length);
  for (let index = 0; index < prereleaseLength; index += 1) {
    const leftIdentifier = parsedLeft.prerelease[index];
    const rightIdentifier = parsedRight.prerelease[index];
    if (leftIdentifier === undefined) return -1;
    if (rightIdentifier === undefined) return 1;
    if (leftIdentifier === rightIdentifier) continue;

    const leftIsNumeric = /^\d+$/.test(leftIdentifier);
    const rightIsNumeric = /^\d+$/.test(rightIdentifier);
    if (leftIsNumeric && rightIsNumeric) return compareNumericIdentifiers(leftIdentifier, rightIdentifier);
    if (leftIsNumeric) return -1;
    if (rightIsNumeric) return 1;
    return leftIdentifier < rightIdentifier ? -1 : 1;
  }

  return 0;
}

export function classifyClientVersion(value: string | null | undefined): ClientVersionClassification {
  const normalized = value?.trim();
  return normalized && parseSemVer(normalized) ? normalized : V1_UNVERSIONED;
}

export function clientVersionIsSupported(clientVersion: string | null | undefined, minimumVersion: string) {
  const classified = classifyClientVersion(clientVersion);
  if (classified === V1_UNVERSIONED) return false;
  if (!parseSemVer(minimumVersion)) throw new Error(`Invalid minimumSupportedClientVersion: ${minimumVersion}`);
  return compareSemVer(classified, minimumVersion) >= 0;
}

export function detectClientDisplayMode(input: {
  fullscreen: boolean;
  iosStandalone?: boolean;
  minimalUi?: boolean;
  standalone: boolean;
}): ClientDisplayMode {
  if (input.fullscreen) return "fullscreen";
  if (input.standalone || input.minimalUi || input.iosStandalone) return "standalone";
  return "browser";
}
