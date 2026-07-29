<script lang="ts">
  import { coverUrl, errorMessage, newCoverPath, shrinkCover, supabase, type Book } from "./lib";

  let {
    position,
    book,
    teacherId,
    listId,
    locked,
    onSaved,
    onRemove,
  }: {
    position: number;
    book?: Book;
    teacherId: string;
    listId: string;
    locked: boolean;
    onSaved: () => void;
    // Gets rid of this card: deletes a saved book, or drops a book being added
    // before it was ever saved.
    onRemove: () => void | Promise<void>;
  } = $props();

  let editing = $state(false);
  let title = $state("");
  let blurb = $state("");
  let cover: File | null = $state(null);
  let preview = $state("");
  let dragging = $state(false);
  let busy = $state(false);
  let error = $state("");

  $effect(() => {
    title = book?.title || "";
    blurb = book?.blurb || "";
    preview = book ? coverUrl(book) : "";
  });

  function setCover(file: File) {
    if (!file.type.startsWith("image/")) {
      error = "Please drop an image file here.";
      return;
    }
    cover = file;
    preview = URL.createObjectURL(file);
    error = "";
  }

  function chooseCover(event: Event) {
    const file = (event.currentTarget as HTMLInputElement).files?.[0];
    if (file) setCover(file);
  }

  async function dropCover(event: DragEvent) {
    event.preventDefault();
    dragging = false;

    const file = [...(event.dataTransfer?.files || [])].find((item) => item.type.startsWith("image/"));
    if (file) {
      setCover(file);
      return;
    }

    const imageUrl = event.dataTransfer?.getData("text/uri-list");
    if (!imageUrl) {
      error = "That does not appear to be an image. Try dragging the image itself.";
      return;
    }

    try {
      const response = await fetch(imageUrl);
      const blob = await response.blob();
      if (!response.ok || !blob.type.startsWith("image/")) throw new Error();
      const name = new URL(imageUrl).pathname.split("/").pop() || "book-cover";
      setCover(new File([blob], name, { type: blob.type }));
    } catch {
      error = "That website blocks direct image sharing. Save the image first, then drag it here.";
    }
  }

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!book && !cover) {
      error = "Add a cover image for this book.";
      return;
    }
    busy = true;
    error = "";
    let uploadedPath = "";
    try {
      // The cover image is stored separately from the book's details, so it is
      // uploaded first and the book row then points at it.
      if (cover) {
        uploadedPath = newCoverPath(teacherId);
        const { error: uploadFailed } = await supabase.storage
          .from("covers")
          .upload(uploadedPath, await shrinkCover(cover), { contentType: "image/webp" });
        if (uploadFailed) throw uploadFailed;
      }

      const details = {
        teacher: teacherId,
        list: listId,
        title: title.trim(),
        blurb: blurb.trim(),
        ...(uploadedPath ? { cover: uploadedPath } : {}),
      };
      // A book takes its place in the list when it is first added, and keeps it
      // through every later edit.
      const { error: saveFailed } = book
        ? await supabase.from("books").update(details).eq("id", book.id)
        : await supabase.from("books").insert({ ...details, position });
      if (saveFailed) throw saveFailed;

      // Only once the new cover is definitely in use can the old one go.
      if (uploadedPath && book?.cover) {
        await supabase.storage.from("covers").remove([book.cover]);
      }
      editing = false;
      cover = null;
      onSaved();
    } catch (caught) {
      if (uploadedPath) await supabase.storage.from("covers").remove([uploadedPath]);
      error = errorMessage(caught);
    } finally {
      busy = false;
    }
  }

  async function remove() {
    if (!book) return;
    if (!confirm(`Remove “${book.title}” from this book list? This cannot be undone.`)) return;
    busy = true;
    await onRemove();
    busy = false;
  }
</script>

<article class="editor-card" class:complete={book}>
  <div class="slot-number">{position}</div>
  {#if book && !editing}
    <img class="editor-cover" src={coverUrl(book)} alt="Cover of {book.title}" />
    <div class="editor-summary">
      <p class="slot-label">Book {position}</p>
      <h3>{book.title}</h3>
      <p>{book.blurb}</p>
    </div>
    <div class="editor-actions">
      <button class="button subtle small" disabled={locked || busy} onclick={() => (editing = true)}>
        {locked ? "Locked" : "Edit"}
      </button>
      {#if !locked}
        <button class="button danger small" disabled={busy} onclick={remove}>
          {busy ? "Removing…" : "Remove"}
        </button>
      {/if}
    </div>
  {:else}
    <form class="book-form" onsubmit={save}>
      <div class="cover-picker">
        <label
          class="cover-drop"
          class:dragging
          ondragenter={(event) => { event.preventDefault(); dragging = true; }}
          ondragover={(event) => event.preventDefault()}
          ondragleave={(event) => { if (!event.currentTarget.contains(event.relatedTarget as Node)) dragging = false; }}
          ondrop={dropCover}
        >
          {#if preview}
            <img src={preview} alt="Book cover preview" />
          {:else}
            <span class="cover-plus">+</span><span>Add or drop cover</span>
          {/if}
          <input type="file" accept="image/jpeg,image/png,image/webp,image/gif" onchange={chooseCover} />
        </label>
      </div>
      <div class="book-fields">
        <p class="slot-label">Book {position}</p>
        <label>Title <input bind:value={title} maxlength="120" required placeholder="Book title" /></label>
        <label>Short description <textarea bind:value={blurb} maxlength="500" required rows="3" placeholder="What might draw students into this story?"></textarea></label>
        {#if error}<p class="message error" role="alert">{error}</p>{/if}
        <div class="button-row">
          <button class="button primary small" disabled={busy}>{busy ? "Saving…" : "Save book"}</button>
          <button class="button text small" type="button" onclick={() => (book ? (editing = false) : onRemove())}>Cancel</button>
        </div>
      </div>
    </form>
  {/if}
</article>
