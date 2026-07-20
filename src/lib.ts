import PocketBase from "pocketbase";

export const pb = new PocketBase(window.location.origin);

export type Book = {
  id: string;
  position: number;
  title: string;
  blurb: string;
  cover: string;
  teacher?: string;
};

export function coverUrl(book: Book, thumb = "240x360") {
  if (!book.cover) return "";
  return pb.files.getURL({ collectionId: "books", id: book.id }, book.cover, { thumb });
}

export function errorMessage(error: unknown) {
  if (error && typeof error === "object" && "response" in error) {
    const response = (error as { response?: { message?: string; data?: Record<string, { message?: string }> } }).response;
    const fieldError = response?.data && Object.values(response.data)[0]?.message;
    return fieldError || response?.message || "Something went wrong. Please try again.";
  }
  return error instanceof Error ? error.message : "Something went wrong. Please try again.";
}
