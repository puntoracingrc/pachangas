import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const editor = readFileSync(new URL("../app/personalizar-carta/page.tsx", import.meta.url), "utf8");
const editorStyles = readFileSync(new URL("../app/personalizar-carta/page.module.css", import.meta.url), "utf8");
const onboarding = readFileSync(new URL("../app/perfil/test-inicial/page.tsx", import.meta.url), "utf8");
const migration = readFileSync(
  new URL("../supabase/migrations/20260905200911_player_avatar_storage_sync_v1.sql", import.meta.url),
  "utf8",
);
const rlsHardening = readFileSync(
  new URL("../supabase/migrations/20260905201103_player_avatar_storage_registered_user_rls_v1.sql", import.meta.url),
  "utf8",
);

test("card personalization returns to the post-test choices after a confirmed save", () => {
  assert.match(onboarding, /personalizar-carta\?returnTo=%2Fperfil%2Ftest-inicial/);
  assert.match(editor, /requestedReturn === "\/perfil\/test-inicial"/);
  assert.match(editor, /if \(!hasPendingChanges\) \{[\s\S]*window\.location\.assign\(returnHref\)/);
  assert.match(editor, /if \(cosmeticsSaved && avatarSaved\) window\.location\.assign\(returnHref\)/);
  assert.doesNotMatch(editor, /primaryDisabled=\{!dirty \|\| !snapshot\?\.enabled\}/);
});

test("the plus action offers a local file and the phone camera", () => {
  assert.match(editor, /aria-label="Elegir foto desde un archivo"/);
  assert.match(editor, /aria-label="Hacer una foto con la cámara"/);
  assert.match(editor, /capture="user"/);
  assert.match(editor, /photoClassName=\{styles\.editablePhoto\}/);
  assert.match(editor, /onClick: \(\) => setPhotoMenuOpen/);
  assert.match(editor, /Elige una imagen del teléfono o haz una foto con la cámara/);
  assert.match(editorStyles, /\.photoMenu/);
  assert.match(editorStyles, /\.editablePhoto:focus-visible/);
});

test("avatar media is reduced locally but only becomes canonical through Supabase", () => {
  assert.match(editor, /canvas\.width = 420/);
  assert.match(editor, /canvas\.height = 540/);
  assert.match(editor, /PLAYER_AVATAR_BUCKET = "pachanga-player-avatars"/);
  assert.match(editor, /bucket\.upload\(objectPath, avatarDraft\.blob/);
  assert.match(editor, /action: "profile\.avatar\.confirm"/);
  assert.match(editor, /expected_revision: socialProfile\.revision/);
  assert.match(editor, /operation_id: avatarDraft\.operationId/);
  assert.match(editor, /await loadIdentity\(\)/);
  assert.doesNotMatch(editor, /localStorage[\s\S]{0,120}avatarDraft/);
});

test("the avatar bucket and universal-profile synchronization are least privilege", () => {
  assert.match(migration, /file_size_limit[\s\S]*1048576/);
  assert.match(migration, /allowed_mime_types[\s\S]*image\/webp[\s\S]*image\/jpeg[\s\S]*image\/png/);
  assert.match(migration, /for insert[\s\S]*to authenticated[\s\S]*storage\.foldername\(name\)\)\[1\] = \(select auth\.uid\(\)\)::text/);
  assert.match(migration, /after update of avatar_ref/);
  assert.match(migration, /update public\.pachanga_player_profiles profiles[\s\S]*set avatar = new\.avatar_ref/);
  assert.match(migration, /profile_version = profiles\.profile_version \+ 1/);
  assert.match(migration, /sync_pachanga_player_profile_to_groups\(target_profile_id\)/);
  assert.match(migration, /'rating_profile', target_profile_id::text, target_profile_revision, new\.user_id/);
  assert.doesNotMatch(migration, /set\s+(rating|current_overall|current_facets)\s*=/i);
  assert.equal((rlsHardening.match(/public\.is_registered_pachanga_user\(\)/g) ?? []).length, 3);
  assert.equal((rlsHardening.match(/storage\.foldername\(name\)/g) ?? []).length, 3);
});
