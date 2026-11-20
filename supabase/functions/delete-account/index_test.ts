import { assertEquals } from "jsr:@std/assert";
import { type Deps, handle } from "./index.ts";

console.error = () => {}; // логи функции не печатаем

function fakeDeps(opts: { user?: string | null; deleteError?: string } = {}) {
  const calls = { getUser: [] as string[], deleteUser: [] as string[] };
  const deps: Deps = {
    getUserID: (jwt) => {
      calls.getUser.push(jwt);
      return Promise.resolve(opts.user === undefined ? "user-1" : opts.user);
    },
    deleteUser: (id) => {
      calls.deleteUser.push(id);
      return Promise.resolve(opts.deleteError ?? null);
    },
  };
  return { deps, calls };
}

const req = (method = "POST", auth: string | null = "Bearer jwt-1") =>
  new Request("http://localhost/delete-account", { method, headers: auth === null ? {} : { authorization: auth } });

Deno.test("удаляет пользователя из JWT", async () => {
  const { deps, calls } = fakeDeps();
  const res = await handle(req(), deps);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { deleted: true });
  assertEquals(calls.getUser, ["jwt-1"]);
  assertEquals(calls.deleteUser, ["user-1"]);
});

Deno.test("без Authorization — 401, никого не удаляет", async () => {
  const { deps, calls } = fakeDeps();
  const res = await handle(req("POST", null), deps);
  assertEquals(res.status, 401);
  await res.body?.cancel();
  assertEquals(calls.getUser, []);
  assertEquals(calls.deleteUser, []);
});

Deno.test("JWT не принят Auth — 401", async () => {
  const { deps, calls } = fakeDeps({ user: null });
  const res = await handle(req(), deps);
  assertEquals(res.status, 401);
  await res.body?.cancel();
  assertEquals(calls.deleteUser, []);
});

Deno.test("не POST — 405", async () => {
  const { deps, calls } = fakeDeps();
  const res = await handle(req("GET"), deps);
  assertEquals(res.status, 405);
  await res.body?.cancel();
  assertEquals(calls.getUser, []);
});

Deno.test("сбой удаления — 500", async () => {
  const { deps } = fakeDeps({ deleteError: "boom" });
  const res = await handle(req(), deps);
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: "delete failed" });
});
