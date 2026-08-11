import { execFileSync } from "node:child_process";
import type { NextConfig } from "next";

const semVerCorePattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

function buildCommitSha() {
  const suppliedSha = process.env.VERCEL_GIT_COMMIT_SHA ?? process.env.GITHUB_SHA;
  if (suppliedSha?.trim()) return suppliedSha.trim();

  try {
    return execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  } catch {
    return "local";
  }
}

function buildReleaseVersion() {
  const releaseVersion = process.env.PACHANGAS_CLIENT_RELEASE_VERSION?.trim() || "2.0.0";
  if (!semVerCorePattern.test(releaseVersion)) {
    throw new Error("PACHANGAS_CLIENT_RELEASE_VERSION must be a SemVer core such as 1.0.0");
  }
  return releaseVersion;
}

const releaseVersion = buildReleaseVersion();
const buildId = buildCommitSha().replace(/[^0-9A-Za-z-]/g, "").slice(0, 12) || "local";
const clientVersion = `${releaseVersion}+${buildId}`;
const serviceWorkerVersion = `${releaseVersion}+sw.${buildId}`;

const pwaIconPaths = [
  "/apple-touch-icon.png",
  "/favicon-16.png",
  "/favicon-32.png",
  "/icon-192.png",
  "/icon-512.png",
  "/icon-maskable-192.png",
  "/icon-maskable-512.png",
  "/icon-monochrome.svg",
];

const nextConfig: NextConfig = {
  env: {
    NEXT_PUBLIC_PACHANGAS_CLIENT_VERSION: clientVersion,
    NEXT_PUBLIC_PACHANGAS_SERVICE_WORKER_VERSION: serviceWorkerVersion,
  },
  async headers() {
    return [
      {
        source: "/sw.js",
        headers: [
          {
            key: "Cache-Control",
            value: "no-cache, no-store, must-revalidate",
          },
          {
            key: "Service-Worker-Allowed",
            value: "/",
          },
        ],
      },
      {
        source: "/manifest.webmanifest",
        headers: [
          {
            key: "Cache-Control",
            value: "public, max-age=3600, must-revalidate",
          },
        ],
      },
      ...pwaIconPaths.map((source) => ({
        source,
        headers: [
          {
            key: "Cache-Control",
            value: "public, max-age=604800, immutable",
          },
        ],
      })),
      {
        source: "/team-shield-premium-v1/:path*",
        headers: [
          {
            key: "Cache-Control",
            value: "public, max-age=31536000, immutable",
          },
        ],
      },
      {
        source: "/admin/:path*",
        headers: [
          { key: "Cache-Control", value: "private, no-store, max-age=0, must-revalidate" },
          { key: "X-Robots-Tag", value: "noindex, nofollow" },
        ],
      },
      {
        source: "/api/platform-admin/:path*",
        headers: [
          { key: "Cache-Control", value: "private, no-store, max-age=0, must-revalidate" },
          { key: "X-Robots-Tag", value: "noindex, nofollow" },
        ],
      },
    ];
  },
};

export default nextConfig;
