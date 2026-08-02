import { evaluateClientPolicy, noStoreHeaders } from "./_contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  return Response.json(evaluateClientPolicy(request.headers), {
    headers: noStoreHeaders,
  });
}
