<script lang="ts">
  import { coverUrl, errorMessage, pb, type Book } from "./lib";

  let {
    position,
    book,
    locked,
    onSaved,
  }: { position: number; book?: Book; locked: boolean; onSaved: () => void } = $props();

  let editing = $state(false);
  let title = $state("");
  let blurb = $state("");
  let cover: File | null = $state(null);
  let preview = $state("");
  let busy = $state(false);
  let error = $state("");

  $effect(() => {
    title = book?.title || "";
    blurb = book?.blurb || "";
    preview = book ? coverUrl(book) : "";
  });

  function chooseCover(event: Event) {
    const file = (event.currentTarget as HTMLInputElement).files?.[0] || null;
    cover = file;
    if (file) preview = URL.createObjectURL(file);
  }

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!book && !cover) {
      error = "Add a cover image for this book.";
      return;
    }
    busy = true;
    error = "";
    try {
      const data = new FormData();
      data.set("teacher", pb.authStore.record!.id);
      data.set("position", String(position));
      data.set("title", title.trim());
      data.set("blurb", blurb.trim());
      if (cover) data.set("cover", cover);
      if (book) await pb.collection("books").update(book.id, data);
      else await pb.collection("books").create(data);
      editing = false;
      cover = null;
      onSaved();
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      busy = false;
    }
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
    <button class="button subtle small" disabled={locked} onclick={() => (editing = true)}>
      {locked ? "Locked" : "Edit"}
    </button>
  {:else}
    <form class="book-form" onsubmit={save}>
      <div class="cover-picker">
        <label class="cover-drop">
          {#if preview}
            <img src={preview} alt="Book cover preview" />
          {:else}
            <span class="cover-plus">+</span><span>Add cover</span>
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
          {#if book}<button class="button text small" type="button" onclick={() => (editing = false)}>Cancel</button>{/if}
        </div>
      </div>
    </form>
  {/if}
</article>
