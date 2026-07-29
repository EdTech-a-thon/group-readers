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
  // A private note on the teacher's dashboard, telling one list from another.
  description: string;
  // How many books every student on this list ranks, chosen by the teacher.
  rankedBooks: number;
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

export const bookListColumns =
  "id, name, description, rankedBooks:ranked_books, shareToken:share_token";

// The app has no router: the address bar decides which page is showing. Pushing
// a URL and then raising the same event the Back button raises means both
// directions of navigation travel one path.
export function navigate(to: string) {
  if (to !== window.location.pathname) history.pushState({}, "", to);
  window.dispatchEvent(new PopStateEvent("popstate"));
}

export function studentLink(list: BookList) {
  return `${window.location.origin}/student/${list.shareToken}`;
}

// A teacher decides both how many books their students rank and how long the
// list is. A list becomes usable once it holds a book for every place in the
// ranking, and thirty is where the database stops accepting more.
export const minimumRankedBooks = 2;
export const maximumRankedBooks = 10;
export const maximumBooks = 30;

// 1st, 2nd, 3rd, 4th — one label for each place in a ranking.
export function ordinal(place: number) {
  const teens = place % 100;
  const suffix =
    teens >= 11 && teens <= 13 ? "th" : ["th", "st", "nd", "rd"][place % 10] || "th";
  return `${place}${suffix}`;
}

export function coverUrl(book: Book) {
  if (!book.cover) return "";
  return supabase.storage.from("covers").getPublicUrl(book.cover).data.publicUrl;
}

// Every cover lives in a folder named after the teacher who uploaded it, which
// is the one place storage permissions allow them to write.
export function newCoverPath(teacherId: string) {
  return `${teacherId}/${crypto.randomUUID()}.webp`;
}

// Takes a book off its list. The database renumbers whatever came after it, so
// the list has no gap where the book used to be. Its cover image can only go
// once the row that pointed at it is gone.
export async function deleteBook(book: Book) {
  const { error: caught } = await supabase.rpc("remove_book", { target_book: book.id });
  if (caught) throw caught;
  if (book.cover) await supabase.storage.from("covers").remove([book.cover]);
}

// Sets up a new book list holding copies of another list's books, so a teacher
// only types the titles, descriptions, and covers once however many classes they
// teach. The copy asks its students to rank as many books as the original did.
// Each copy gets its own cover image file, so editing or clearing one list never
// disturbs the other.
export async function duplicateBookList(
  teacherId: string,
  source: BookList,
  details: { name: string; description: string },
  sourceBooks: Book[],
) {
  const { data, error: createFailed } = await supabase
    .from("book_lists")
    .insert({ ...details, ranked_books: source.rankedBooks })
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
  [/book_lists_ranked_books_check/i, `Students can rank from ${minimumRankedBooks} to ${maximumRankedBooks} books.`],
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
