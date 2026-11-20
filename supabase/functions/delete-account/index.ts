// Edge Function delete-account (D31): удаляет пользователя по его JWT. Строки закладок, подписок и позиций
// уходят каскадом (on delete cascade). Отзыв токена Apple — когда появится вход через Apple.
import { createClient } from "npm:@supabase/supabase-js@2";

export type Deps = {
  getUserID: (jwt: string) => Promise<string | null>; // null — токен не принят Auth
  deleteUser: (id: string) => Promise<string | null>; // текст ошибки или null
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST") return reply({ error: "method not allowed" }, 405);
  const jwt = req.headers.get("authorization")?.match(/^Bearer (.+)$/)?.[1];
  if (!jwt) return reply({ error: "unauthorized" }, 401);
  const id = await deps.getUserID(jwt);
  if (!id) return reply({ error: "unauthorized" }, 401);
  const error = await deps.deleteUser(id);
  if (error) {
    console.error(`delete-account: ${error}`);
    return reply({ error: "delete failed" }, 500);
  }
  return reply({ deleted: true });
}

if (import.meta.main) {
  const url = Deno.env.get("SUPABASE_URL")!;
  const options = { auth: { persistSession: false } };
  // Токен проверяет сам Auth (getUser), поэтому verify_jwt шлюза выключен в config.toml.
  const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, options);
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, options);
  Deno.serve((req) =>
    handle(req, {
      getUserID: async (jwt) => {
        const { data, error } = await anon.auth.getUser(jwt);
        return error ? null : data.user?.id ?? null;
      },
      deleteUser: async (id) => (await admin.auth.admin.deleteUser(id)).error?.message ?? null,
    })
  );
}
