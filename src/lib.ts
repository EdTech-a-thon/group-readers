import { createClient } from "@supabase/supabase-js";

export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY,
);

// A teacher keeps one book list per group of students they teach. Each list has
// its own books, its own student link, and its own responses.
export type BookList = {
  id: string;
  name: string;
  shareToken: string;
};

export type Book = {
  id: string;
  position: number;
  title: string;
  blurb: string;
  cover: string;
  teacher?: string;
  list?: string;
};

export const bookListColumns = "id, name, shareToken:share_token";

export function coverUrl(book: Book) {
  if (!book.cover) return "";
  return supabase.storage.from("covers").getPublicUrl(book.cover).data.publicUrl;
}

// Every cover lives in a folder named after the teacher who uploaded it, which
// is the one place storage permissions allow them to write.
export function newCoverPath(teacherId: string) {
  return `${teacherId}/${crypto.randomUUID()}.webp`;
}

// Sets up a new book list holding copies of another list's books, so a teacher
// only types the titles, descriptions, and covers once however many classes they
// teach. Each copy gets its own cover image file, so editing or clearing one
// list never disturbs the other.
export async function duplicateBookList(teacherId: string, name: string, sourceBooks: Book[]) {
  const { data, error: createFailed } = await supabase
    .from("book_lists")
    .insert({ name })
    .select(bookListColumns)
    .single();
  if (createFailed) throw createFailed;

  const created = data as BookList;
  const copiedCovers: string[] = [];
  try {
    const rows: Record<string, unknown>[] = [];
    for (const book of sourceBooks) {
      const cover = newCoverPath(teacherId);
      const { error: copyFailed } = await supabase.storage.from("covers").copy(book.cover, cover);
      if (copyFailed) throw copyFailed;
      copiedCovers.push(cover);
      rows.push({
        teacher: teacherId,
        list: created.id,
        position: book.position,
        title: book.title,
        blurb: book.blurb,
        cover,
      });
    }

    if (rows.length) {
      const { error: insertFailed } = await supabase.from("books").insert(rows);
      if (insertFailed) throw insertFailed;
    }
    return created;
  } catch (caught) {
    // Never leave a half-copied list behind: deleting the list row takes its
    // books with it, and the covers we just made go too.
    if (copiedCovers.length) await supabase.storage.from("covers").remove(copiedCovers);
    await supabase.from("book_lists").delete().eq("id", created.id);
    throw caught;
  }
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
  [/book_lists_name_check/i, "Give your book list a name of 1 to 60 characters."],
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
