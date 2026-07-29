<script lang="ts">
  import { onMount } from "svelte";
  import BookEditor from "./BookEditor.svelte";
  import GroupBuilder from "./GroupBuilder.svelte";
  import TopBar from "./TopBar.svelte";
  import {
    bookListColumns,
    coverUrl,
    deleteBook,
    errorMessage,
    maximumBooks,
    minimumBooks,
    navigate,
    studentLink,
    supabase,
    type Book,
    type BookList,
  } from "./lib";

  let { listId, onSignOut }: { listId: string; onSignOut: () => void } = $props();

  let teacherId = $state("");
  let username = $state("Teacher");
  let list = $state<BookList>();
  let books = $state<Book[]>([]);
  let submissions = $state<any[]>([]);
  let savedPlan = $state<any>();
  let loading = $state(true);
  let gone = $state(false);
  let error = $state("");
  let copied = $state(false);
  let clearing = $state(false);
  let randomCount = $state(10);
  let addingRandom = $state(false);
  let clearingBooks = $state(false);
  let adding = $state(false);
  let view = $state<"books" | "results" | "groups">("books");

  const locked = $derived(submissions.length > 0);
  // A list is as long as its teacher wants it; it is ready for students as soon
  // as there are enough books to rank.
  const ready = $derived(books.length >= minimumBooks);
  const missing = $derived(Math.max(0, minimumBooks - books.length));

  onMount(async () => {
    await load();
    loading = false;
  });

  async function load() {
    error = "";
    try {
      const [teacher, listRow, bookRows, responseRows, planRows] = await Promise.all([
        supabase.from("teachers").select("id, username").single(),
        supabase.from("book_lists").select(bookListColumns).eq("id", listId).maybeSingle(),
        supabase
          .from("books")
          .select("id, position, title, blurb, cover")
          .eq("list", listId)
          .order("position"),
        supabase
          .from("submissions")
          .select("id, firstName:first_name, lastInitial:last_initial, choices")
          .eq("list", listId)
          .order("first_name")
          .order("last_initial"),
        supabase.from("grouping_plans").select("settings, result").eq("list", listId),
      ]);

      for (const response of [teacher, listRow, bookRows, responseRows, planRows]) {
        if (response.error) throw response.error;
      }

      teacherId = teacher.data!.id;
      username = teacher.data!.username;
      // A list that cannot be read either never existed or belongs to somebody
      // else; either way this teacher has nothing to open here.
      list = (listRow.data || undefined) as BookList | undefined;
      gone = !list;
      books = (bookRows.data || []) as Book[];
      submissions = responseRows.data || [];
      savedPlan = planRows.data?.[0];
    } catch (caught) {
      error = errorMessage(caught);
    }
  }

  async function copyLink() {
    if (!list) return;
    await navigator.clipboard.writeText(studentLink(list));
    copied = true;
    setTimeout(() => (copied = false), 1800);
  }

  async function addedBook() {
    adding = false;
    await load();
  }

  async function removeBook(book: Book) {
    error = "";
    try {
      await deleteBook(book);
    } catch (caught) {
      error = errorMessage(caught);
    }
    await load();
  }

  async function clearResponses() {
    if (!confirm(`Clear every student response for “${list?.name}”? This cannot be undone.`)) return;
    clearing = true;
    try {
      const { error: caught } = await supabase.rpc("clear_responses", { target_list: listId });
      if (caught) throw caught;
      submissions = [];
      savedPlan = undefined;
      view = "books";
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      clearing = false;
    }
  }

  async function addRandomResponses() {
    const count = Number(randomCount);
    if (!Number.isInteger(count) || count < 1 || count > 100) {
      error = "Choose a number from 1 to 100.";
      return;
    }
    error = "";
    addingRandom = true;
    try {
      const { error: caught } = await supabase.rpc("add_random_responses", {
        target_list: listId,
        response_count: count,
      });
      if (caught) throw caught;
      await load();
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      addingRandom = false;
    }
  }

  async function clearBooks() {
    if (!confirm(`Remove every book from “${list?.name}”? This cannot be undone.`)) return;
    clearingBooks = true;
    error = "";
    try {
      const covers = books.map((book) => book.cover).filter(Boolean);
      const { error: caught } = await supabase.from("books").delete().eq("list", listId);
      if (caught) throw caught;
      if (covers.length) await supabase.storage.from("covers").remove(covers);
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      clearingBooks = false;
      await load();
    }
  }

  function choiceBook(submission: any, index: number): Book | undefined {
    const choiceId = submission.choices[index];
    return books.find((book) => book.id === choiceId);
  }

  function countAt(bookId: string, rank?: number) {
    return submissions.filter((submission) =>
      rank === undefined ? submission.choices.includes(bookId) : submission.choices[rank] === bookId,
    ).length;
  }
</script>

<TopBar {username} {onSignOut} />

<main class="dashboard shell">
  <button class="back-link" onclick={() => navigate("/")}>← All book lists</button>

  {#if loading}
    <div class="center-block"><div class="loader"></div></div>
  {:else if gone}
    <div class="empty-state">
      <h3>This book list is not here</h3>
      <p>It may have been deleted. Go back to your dashboard to pick another one.</p>
      <p><button class="button primary" onclick={() => navigate("/")}>Back to my book lists</button></p>
    </div>
  {:else}
    <section class="dashboard-heading">
      <div>
        <p class="eyebrow">Book list</p>
        <h1>{list?.name}</h1>
        {#if list?.description}<p class="list-note">{list.description}</p>{/if}
        <p>Add as many books as your class needs — at least {minimumBooks}, since every student ranks four. Once the first student responds, this list stays locked to keep every ranking accurate.</p>
      </div>
      <!-- The ring fills as the list reaches the point where students can use it,
           and stays full however many books are added after that. -->
      <div class="progress-ring" style={`--progress:${Math.min(1, books.length / minimumBooks) * 100}%`}>
        <strong>{books.length}</strong><span>{books.length === 1 ? "book" : "books"}</span>
      </div>
    </section>

    <nav class="dashboard-tabs" aria-label="Book list sections">
      <button class:active={view === "books"} onclick={() => (view = "books")}>Books <span>{books.length}</span></button>
      <button class:active={view === "results"} onclick={() => (view = "results")}>Student choices <span>{submissions.length}</span></button>
      <button class:active={view === "groups"} onclick={() => (view = "groups")}>Create groups <span>{savedPlan ? "✓" : ""}</span></button>
    </nav>

    {#if error}<p class="message error" role="alert">{error}</p>{/if}

    {#if view === "books"}
      {#if locked}
        <div class="notice locked-notice"><strong>“{list?.name}” is locked.</strong><span>Student choices are coming in. Clear all responses if you need to edit the books.</span></div>
      {/if}
      {#if books.length}
        <div class="book-list-actions">
          <button class="button danger subtle small" disabled={locked || clearingBooks} onclick={clearBooks}>{clearingBooks ? "Clearing…" : "Clear book list"}</button>
        </div>
      {/if}
      <section class="editor-list">
        {#each books as book, index (book.id)}
          <BookEditor
            position={index + 1}
            {book}
            {teacherId}
            {listId}
            {locked}
            onSaved={load}
            onRemove={() => removeBook(book)}
          />
        {/each}
        {#if !locked}
          {#if adding}
            <BookEditor
              position={books.length + 1}
              {teacherId}
              {listId}
              {locked}
              onSaved={addedBook}
              onRemove={() => {
                adding = false;
              }}
            />
          {:else if books.length < maximumBooks}
            <button class="add-book" onclick={() => (adding = true)}>
              <span class="cover-plus">+</span>
              <span>Add book {books.length + 1}</span>
            </button>
          {:else}
            <p class="list-full">This list is full at {maximumBooks} books. Remove one to make room for another.</p>
          {/if}
        {/if}
      </section>

      <aside class="share-card" class:ready>
        <div>
          <p class="eyebrow">Student invitation</p>
          <h2>{ready ? `The link for ${list?.name} is ready` : `${missing} ${missing === 1 ? "book" : "books"} to go`}</h2>
          <p>{ready ? `Only the students you send this link to can answer, so their choices stay separate from your other book lists. They do not need an account.` : `A list needs at least ${minimumBooks} books before students can rank four of them.`}</p>
        </div>
        {#if ready && list}
          <div class="share-actions"><input value={studentLink(list)} readonly aria-label="Student link" /><button class="button accent" onclick={copyLink}>{copied ? "Copied!" : "Copy link"}</button></div>
        {/if}
      </aside>
    {:else if view === "results"}
      <section class="results-head">
        <div><p class="eyebrow">{list?.name}</p><h2>{submissions.length} {submissions.length === 1 ? "student has" : "students have"} ranked their books</h2></div>
        <div class="response-actions">
          <label>Test responses <input aria-label="Number of random test responses" type="number" min="1" max="100" bind:value={randomCount} /></label>
          <button class="button subtle" disabled={addingRandom || !ready} onclick={addRandomResponses}>{addingRandom ? "Adding…" : "Add random"}</button>
          {#if submissions.length}<button class="button danger subtle" disabled={clearing || addingRandom} onclick={clearResponses}>{clearing ? "Clearing…" : "Clear all responses"}</button>{/if}
        </div>
      </section>

      {#if submissions.length === 0}
        <div class="empty-state"><div class="empty-books">1&nbsp; 2&nbsp; 3&nbsp; 4</div><h3>No choices yet</h3><p>Once students use this list's link, their ranked choices will appear here.</p></div>
      {:else}
        <section class="summary-grid">
          {#each books as book}
            <article class="summary-card">
              <img src={coverUrl(book)} alt="" />
              <div><h3>{book.title}</h3><strong>{countAt(book.id)}</strong><span>top-four picks</span></div>
              <div class="rank-dots" title="First, second, third, and fourth choice counts">
                {#each [0, 1, 2, 3] as rank}<span><b>{rank + 1}</b>{countAt(book.id, rank)}</span>{/each}
              </div>
            </article>
          {/each}
        </section>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Student</th><th>1st choice</th><th>2nd choice</th><th>3rd choice</th><th>4th choice</th></tr></thead>
            <tbody>
              {#each submissions as submission}
                <tr><th>{submission.firstName} {submission.lastInitial}.</th>{#each [0, 1, 2, 3] as rank}<td>{choiceBook(submission, rank)?.title || "—"}</td>{/each}</tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    {:else}
      <GroupBuilder {books} {submissions} {savedPlan} {listId} onSaved={load} />
    {/if}
  {/if}
</main>
