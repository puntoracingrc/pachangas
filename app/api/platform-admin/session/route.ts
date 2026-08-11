import { cookies } from "next/headers";
import {
  PLATFORM_ADMIN_COOKIE,
  PLATFORM_ADMIN_REQUEST_HEADER,
  platformErrorResponse,
  platformJson,
  requireSameOriginMutation,
  verifyPlatformToken,
} from "../../../admin/_lib/platform-auth";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requireSameOriginMutation(request);
    const authorization = request.headers.get("authorization") ?? "";
    const token = authorization.replace(/^Bearer\s+/i, "").trim();
    const session = await verifyPlatformToken(token);
    const store = await cookies();
    store.set(PLATFORM_ADMIN_COOKIE, token, {
      httpOnly: true,
      maxAge: 45 * 60,
      path: "/",
      sameSite: "strict",
      secure: process.env.NODE_ENV === "production",
    });
    return platformJson({ access: session.access });
  } catch (error) {
    return platformErrorResponse(error);
  }
}

export async function DELETE(request: Request) {
  try {
    requireSameOriginMutation(request);
    if (request.headers.get(PLATFORM_ADMIN_REQUEST_HEADER) !== "1") throw new Error("Invalid request");
    const store = await cookies();
    store.delete(PLATFORM_ADMIN_COOKIE);
    return platformJson({ cleared: true });
  } catch (error) {
    return platformErrorResponse(error);
  }
}
