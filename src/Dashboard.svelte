<script lang="ts">
  import { onMount } from "svelte";
  import BookEditor from "./BookEditor.svelte";
  import BookListBar from "./BookListBar.svelte";
  import GroupBuilder from "./GroupBuilder.svelte";
  import { bookListColumns, coverUrl, errorMessage, supabase, type Book, type BookList } from "./lib";

  // Which book list the teacher had open last, so a plain visit to the site
  // returns them to the class they were working on.
  const storedList = "groupReaders.list";

  let { onSignOut }: { onSignOut: () => void } = $props();
  let teacherId = $state("");
  let username = $state("Teacher");
  let lists = $state<BookList[]>([]);
  let activeListId = $state("");
  let books = $state<Book[]>([]);
  let submissions = $state<any[]>([]);
  let savedPlan = $state<any>();
  let loading = $state(true);
  let switching = $state(false);
  let error = $state("");
  let copied = $state(false);
  let clearing = $state(false);
  let randomCount = $state(10);
  let addingRandom = $state(false);
  let clearingBooks = $state(false);
  let view = $state<"books" | "results" | "groups">("books");

  const activeList = $derived(lists.find((list) => list.id === activeListId));
  const listName = $derived(activeList?.name || "your class");
  const shareUrl = $derived(
    activeList ? `${window.location.origin}/student/${activeList.shareToken}` : "",
  );
  const locked = $derived(submissions.length > 0);
  const complete = $derived(books.length === 10);

  onMount(async () => {
    await loadLists();
    loading = false;
  });

  // The teacher and their book lists change rarely; the books, responses, and
  // groups belong to one list and are reloaded whenever the open list changes.
  async function loadLists(preferredId?: string) {
    error = "";
    try {
      const [teacher, listRows] = await Promise.all([
        supabase.from("teachers").select("id, username").single(),
        supabase.from("book_lists").select(bookListColumns).order("created_at"),
      ]);

      for (const response of [teacher, listRows]) {
        if (response.error) throw response.error;
      }

      teacherId = teacher.data!.id;
      username = teacher.data!.username;
      lists = (listRows.data || []) as BookList[];

      const known = (id?: string | null) => Boolean(id && lists.some((list) => list.id === id));
      const wanted = [
        preferredId,
        activeListId,
        new URLSearchParams(window.location.search).get("list"),
        localStorage.getItem(storedList),
      ].find(known);

      const target = wanted || lists[0]?.id;
      if (target) await openList(target);
    } catch (caught) {
      error = errorMessage(caught);
    }
  }

  async function openList(id: string) {
    // Only a genuine change of list blanks the page; ordinary refreshes leave
    // what is already on screen in place.
    switching = Boolean(activeListId) && id !== activeListId;
    activeListId = id;
    localStorage.setItem(storedList, id);
    const url = new URL(window.location.href);
    url.searchParams.set("list", id);
    history.replaceState({}, "", url);
    await loadList();
    switching = false;
  }

  async function loadList() {
    const id = activeListId;
    error = "";
    try {
      const [bookRows, responseRows, planRows] = await Promise.all([
        supabase
          .from("books")
          .select("id, position, title, blurb, cover")
          .eq("list", id)
          .order("position"),
        supabase
          .from("submissions")
          .select("id, firstName:first_name, lastInitial:last_initial, choices")
          .eq("list", id)
          .order("first_name")
          .order("last_initial"),
        supabase.from("grouping_plans").select("settings, result").eq("list", id),
      ]);

      for (const response of [bookRows, responseRows, planRows]) {
        if (response.error) throw response.error;
      }

      books = (bookRows.data || []) as Book[];
      submissions = responseRows.data || [];
      savedPlan = planRows.data?.[0];
    } catch (caught) {
      error = errorMessage(caught);
    }
  }

  async function copyLink() {
    await navigator.clipboard.writeText(shareUrl);
    copied = true;
    setTimeout(() => (copied = false), 1800);
  }

  async function clearResponses() {
    if (!confirm(`Clear every student response for “${listName}”? This cannot be undone.`)) return;
    clearing = true;
    try {
      const { error: caught } = await supabase.rpc("clear_responses", { target_list: activeListId });
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
        target_list: activeListId,
        response_count: count,
      });
      if (caught) throw caught;
      await loadList();
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      addingRandom = false;
    }
  }

  async function clearBooks() {
    if (!confirm(`Remove every book from “${listName}”? This cannot be undone.`)) return;
    clearingBooks = true;
    error = "";
    try {
      const covers = books.map((book) => book.cover).filter(Boolean);
      const { error: caught } = await supabase.from("books").delete().eq("list", activeListId);
      if (caught) throw caught;
      if (covers.length) await supabase.storage.from("covers").remove(covers);
      books = [];
      savedPlan = undefined;
    } catch (caught) {
      error = errorMessage(caught);
      await loadList();
    } finally {
      clearingBooks = false;
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

<header class="topbar">
  <a class="brand" href="/"><span class="brand-mark">G</span><span>Group Readers</span></a>
  <div class="teacher-menu"><span class="avatar">{username.slice(0, 1).toUpperCase()}</span><span>{username}</span><button class="text-link" onclick={onSignOut}>Sign out</button></div>
</header>

<main class="dashboard shell">
  <section class="dashboard-heading">
    <div>
      <p class="eyebrow">{activeList ? listName : "Your classroom"}</p>
      <h1>Build the shelf they’ll choose from.</h1>
      <p>Add exactly ten books. Once the first student responds, this list stays locked to keep every ranking accurate.</p>
    </div>
    <div class="progress-ring" style={`--progress:${books.length * 10}%`}><strong>{books.length}</strong><span>of 10</span></div>
  </section>

  {#if !loading}
    <BookListBar
      {lists}
      activeId={activeListId}
      {teacherId}
      {books}
      onSwitch={openList}
      onChanged={loadLists}
    />
  {/if}

  <nav class="dashboard-tabs" aria-label="Dashboard sections">
    <button class:active={view === "books"} onclick={() => (view = "books")}>Books <span>{books.length}/10</span></button>
    <button class:active={view === "results"} onclick={() => (view = "results")}>Student choices <span>{submissions.length}</span></button>
    <button class:active={view === "groups"} onclick={() => (view = "groups")}>Create groups <span>{savedPlan ? "✓" : ""}</span></button>
  </nav>

  {#if error}<p class="message error" role="alert">{error}</p>{/if}
  {#if loading || switching}
    <div class="center-block"><div class="loader"></div></div>
  {:else if !activeList}
    <div class="empty-state"><h3>No book list yet</h3><p>Create your first book list above to start adding books.</p></div>
  {:else if view === "books"}
    {#if locked}
      <div class="notice locked-notice"><strong>“{listName}” is locked.</strong><span>Student choices are coming in. Clear all responses if you need to edit the books.</span></div>
    {/if}
    {#if books.length}
      <div class="book-list-actions">
        <button class="button danger subtle small" disabled={locked || clearingBooks} onclick={clearBooks}>{clearingBooks ? "Clearing…" : "Clear book list"}</button>
      </div>
    {/if}
    <section class="editor-list">
      {#each Array(10) as _, index}
        <BookEditor position={index + 1} book={books.find((book) => book.position === index + 1)} {teacherId} listId={activeListId} {locked} onSaved={loadList} />
      {/each}
    </section>

    <aside class="share-card" class:ready={complete}>
      <div>
        <p class="eyebrow">Student invitation</p>
        <h2>{complete ? `The link for ${listName} is ready` : `${10 - books.length} books to go`}</h2>
        <p>{complete ? `Only ${listName} gets this link, so their choices stay separate from your other book lists. Students do not need an account.` : "Finish all ten books to open student ranking."}</p>
      </div>
      {#if complete}
        <div class="share-actions"><input value={shareUrl} readonly aria-label="Student link" /><button class="button accent" onclick={copyLink}>{copied ? "Copied!" : "Copy link"}</button></div>
      {/if}
    </aside>
  {:else if view === "results"}
    <section class="results-head">
      <div><p class="eyebrow">{listName}</p><h2>{submissions.length} {submissions.length === 1 ? "student has" : "students have"} ranked their books</h2></div>
      <div class="response-actions">
        <label>Test responses <input aria-label="Number of random test responses" type="number" min="1" max="100" bind:value={randomCount} /></label>
        <button class="button subtle" disabled={addingRandom || !complete} onclick={addRandomResponses}>{addingRandom ? "Adding…" : "Add random"}</button>
        {#if submissions.length}<button class="button danger subtle" disabled={clearing || addingRandom} onclick={clearResponses}>{clearing ? "Clearing…" : "Clear all responses"}</button>{/if}
      </div>
    </section>

    {#if submissions.length === 0}
      <div class="empty-state"><div class="empty-books">1&nbsp; 2&nbsp; 3&nbsp; 4</div><h3>No choices yet</h3><p>Once students use your link, their ranked choices will appear here.</p></div>
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
    <!-- Keyed on the list so switching classes starts the group settings over
         from that list's own saved plan. -->
    {#key activeListId}
      <GroupBuilder {books} {submissions} {savedPlan} listId={activeListId} onSaved={loadList} />
    {/key}
  {/if}
</main>
