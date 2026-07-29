<script lang="ts">
  import { onMount } from "svelte";
  import BookEditor from "./BookEditor.svelte";
  import GroupBuilder from "./GroupBuilder.svelte";
  import { coverUrl, errorMessage, pb, type Book } from "./lib";

  let { onSignOut }: { onSignOut: () => void } = $props();
  let books = $state<Book[]>([]);
  let submissions = $state<any[]>([]);
  let savedPlan = $state<any>();
  let loading = $state(true);
  let error = $state("");
  let copied = $state(false);
  let clearing = $state(false);
  let randomCount = $state(10);
  let addingRandom = $state(false);
  let clearingBooks = $state(false);
  let view = $state<"books" | "results" | "groups">("books");

  const username = pb.authStore.record?.username || "Teacher";
  const shareToken = pb.authStore.record?.shareToken || "";
  const shareUrl = `${window.location.origin}/student/${shareToken}`;
  const locked = $derived(submissions.length > 0);
  const complete = $derived(books.length === 10);

  onMount(loadAll);

  async function loadAll() {
    error = "";
    try {
      const [bookRecords, responseRecords, planRecords] = await Promise.all([
        pb.collection("books").getFullList({ sort: "position" }),
        pb.collection("submissions").getFullList({ sort: "firstName,lastInitial", expand: "choices" }),
        pb.collection("grouping_plans").getFullList(),
      ]);
      books = bookRecords as unknown as Book[];
      submissions = responseRecords;
      savedPlan = planRecords[0];
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      loading = false;
    }
  }

  async function copyLink() {
    await navigator.clipboard.writeText(shareUrl);
    copied = true;
    setTimeout(() => (copied = false), 1800);
  }

  async function clearResponses() {
    if (!confirm("Clear every student response? This cannot be undone.")) return;
    clearing = true;
    try {
      await pb.send("/api/bookclub/clear", { method: "POST" });
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
      await pb.send("/api/bookclub/random-responses", { method: "POST", body: { count } });
      await loadAll();
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      addingRandom = false;
    }
  }

  async function clearBooks() {
    if (!confirm("Remove every book from your list? This cannot be undone.")) return;
    clearingBooks = true;
    error = "";
    try {
      await Promise.all(books.map((book) => pb.collection("books").delete(book.id)));
      books = [];
      savedPlan = undefined;
    } catch (caught) {
      error = errorMessage(caught);
      await loadAll();
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
  <a class="brand" href="/"><span class="brand-mark">B</span><span>Book Club Builder</span></a>
  <div class="teacher-menu"><span class="avatar">{username.slice(0, 1).toUpperCase()}</span><span>{username}</span><button class="text-link" onclick={onSignOut}>Sign out</button></div>
</header>

<main class="dashboard shell">
  <section class="dashboard-heading">
    <div>
      <p class="eyebrow">Your classroom</p>
      <h1>Build the shelf they’ll choose from.</h1>
      <p>Add exactly ten books. Once the first student responds, your list stays locked to keep every ranking accurate.</p>
    </div>
    <div class="progress-ring" style={`--progress:${books.length * 10}%`}><strong>{books.length}</strong><span>of 10</span></div>
  </section>

  <nav class="dashboard-tabs" aria-label="Dashboard sections">
    <button class:active={view === "books"} onclick={() => (view = "books")}>Book list <span>{books.length}/10</span></button>
    <button class:active={view === "results"} onclick={() => (view = "results")}>Student choices <span>{submissions.length}</span></button>
    <button class:active={view === "groups"} onclick={() => (view = "groups")}>Create groups <span>{savedPlan ? "✓" : ""}</span></button>
  </nav>

  {#if error}<p class="message error" role="alert">{error}</p>{/if}
  {#if loading}
    <div class="center-block"><div class="loader"></div></div>
  {:else if view === "books"}
    {#if locked}
      <div class="notice locked-notice"><strong>Your book list is locked.</strong><span>Student choices are coming in. Clear all responses if you need to edit the books.</span></div>
    {/if}
    {#if books.length}
      <div class="book-list-actions">
        <button class="button danger subtle small" disabled={locked || clearingBooks} onclick={clearBooks}>{clearingBooks ? "Clearing…" : "Clear book list"}</button>
      </div>
    {/if}
    <section class="editor-list">
      {#each Array(10) as _, index}
        <BookEditor position={index + 1} book={books.find((book) => book.position === index + 1)} {locked} onSaved={loadAll} />
      {/each}
    </section>

    <aside class="share-card" class:ready={complete}>
      <div>
        <p class="eyebrow">Student invitation</p>
        <h2>{complete ? "Your student link is ready" : `${10 - books.length} books to go`}</h2>
        <p>{complete ? "Share this private link with your class. Students do not need an account." : "Finish all ten books to open student ranking."}</p>
      </div>
      {#if complete}
        <div class="share-actions"><input value={shareUrl} readonly aria-label="Student link" /><button class="button accent" onclick={copyLink}>{copied ? "Copied!" : "Copy link"}</button></div>
      {/if}
    </aside>
  {:else if view === "results"}
    <section class="results-head">
      <div><p class="eyebrow">Class responses</p><h2>{submissions.length} {submissions.length === 1 ? "student has" : "students have"} ranked their books</h2></div>
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
    <GroupBuilder {books} {submissions} {savedPlan} onSaved={loadAll} />
  {/if}
</main>
