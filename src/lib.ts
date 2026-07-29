import { createClient } from "@supabase/supabase-js";

export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY,
);

export type Book = {
  id: string;
  position: number;
  title: string;
  blurb: string;
  cover: string;
  teacher?: string;
};

export function coverUrl(book: Book) {
  if (!book.cover) return "";
  return supabase.storage.from("covers").getPublicUrl(book.cover).data.publicUrl;
}

// Covers are shown at roughly 240x360, so shrinking them before upload keeps
// the dashboard and the student page quick to load.
export async function shrinkCover(file: File, maxWidth = 480, maxHeight = 720) {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxWidth / bitmap.width, maxHeight / bitmap.height);
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();

  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, "image/webp", 0.85),
  );
  if (!blob) throw new Error("We could not read that image. Try a different file.");
  return blob;
}

const friendlyMessages: [RegExp, string][] = [
  [/already registered/i, "An account with that email already exists. Try signing in instead."],
  [/invalid login credentials/i, "That email or password is not right."],
  [/teachers_username_key/i, "Another teacher is already using that name."],
  [/teachers_username_check/i, "Names can be 3 to 30 letters, numbers, spaces, or . _ - ' characters."],
  [/database error saving new user/i, "We could not create that account. Try a different name."],
];

export function errorMessage(error: unknown) {
  const raw =
    error && typeof error === "object" && "message" in error
      ? String((error as { message?: string }).message || "")
      : "";
  if (!raw) return "Something went wrong. Please try again.";

  for (const [pattern, friendly] of friendlyMessages) {
    if (pattern.test(raw)) return friendly;
  }
  return raw;
}
