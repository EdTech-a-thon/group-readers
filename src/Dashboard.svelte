<script lang="ts">
  import { onMount } from "svelte";
  import TopBar from "./TopBar.svelte";
  import {
    bookListColumns,
    duplicateBookList,
    errorMessage,
    minimumBooks,
    navigate,
    studentLink,
    supabase,
    type Book,
    type BookList,
  } from "./lib";

  // One panel writes a new list, a copy of one, and an edit to one, since all
  // three ask for exactly a name and a description.
  type Draft = {
    mode: "new" | "copy" | "edit";
    source?: BookList;
    name: string;
    description: string;
  };

  let { onSignOut }: { onSignOut: () => void } = $props();

  let teacherId = $state("");
  let username = $state("Teacher");
  let lists = $state<BookList[]>([]);
  let books = $state<Book[]>([]);
  let responded = $state<string[]>([]);
  let planned = $state<string[]>([]);
  let loading = $state(true);
  let busy = $state(false);
  let error = $state("");
  let copiedId = $state("");
  let draft = $state<Draft>();

  onMount(async () => {
    await load();
    loading = false;
  });

  // One pass over everything this teacher owns. The books come along in full
  // rather than as counts, because duplicating a list needs them anyway.
  async function load() {
    error = "";
    try {
      const [teacher, listRows, bookRows, responseRows, planRows] = await Promise.all([
        supabase.from("teachers").select("id, username").single(),
        supabase.from("book_lists").select(bookListColumns).order("created_at"),
        supabase.from("books").select("id, list, position, title, blurb, cover").order("position"),
        supabase.from("submissions").select("list"),
        supabase.from("grouping_plans").select("list"),
      ]);

      for (const response of [teacher, listRows, bookRows, responseRows, planRows]) {
        if (response.error) throw response.error;
      }

      teacherId = teacher.data!.id;
      username = teacher.data!.username;
      lists = (listRows.data || []) as BookList[];
      books = (bookRows.data || []) as Book[];
      responded = (responseRows.data || []).map((row: any) => row.list);
      planned = (planRows.data || []).map((row: any) => row.list);
    } catch (caught) {
      error = errorMessage(caught);
    }
  }

  function booksIn(listId: string) {
    return books.filter((book) => book.list === listId);
  }

  function responsesIn(listId: string) {
    return responded.filter((id) => id === listId).length;
  }

  async function copyLink(list: BookList) {
    await navigator.clipboard.writeText(studentLink(list));
    copiedId = list.id;
    setTimeout(() => (copiedId = ""), 1800);
  }

  async function saveDraft(event: SubmitEvent) {
    event.preventDefault();
    if (!draft) return;

    const details = { name: draft.name.trim(), description: draft.description.trim() };
    if (!details.name) {
      error = "Give your book list a name.";
      return;
    }

    const { mode, source } = draft;
    busy = true;
    error = "";
    try {
      if (mode === "copy" && source) {
        // A fresh copy is somewhere the teacher wants to be, so open it.
        const copy = await duplicateBookList(teacherId, details, booksIn(source.id));
        draft = undefined;
        navigate(`/list/${copy.id}`);
        return;
      }

      const { error: caught } =
        mode === "edit" && source
          ? await supabase.from("book_lists").update(details).eq("id", source.id)
          : await supabase.from("book_lists").insert(details);
      if (caught) throw caught;

      draft = undefined;
      await load();
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      busy = false;
    }
  }

  async function remove(list: BookList) {
    if (!confirm(`Delete “${list.name}”, its books, and its student responses? This cannot be undone.`)) return;
    busy = true;
    error = "";
    try {
      // The books go when the list goes, but their cover images have to be
      // cleared out by hand.
      const covers = booksIn(list.id).map((book) => book.cover).filter(Boolean);
      const { error: caught } = await supabase.from("book_lists").delete().eq("id", list.id);
      if (caught) throw caught;
      if (covers.length) await supabase.storage.from("covers").remove(covers);
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      busy = false;
      await load();
    }
  }
</script>

<TopBar {username} {onSignOut} />

<main class="dashboard shell">
  <section class="dashboard-heading">
    <div>
      <p class="eyebrow">Teacher dashboard</p>
      <h1>Your book lists.</h1>
      <p>Keep one list for every group of students you teach. Each has its own student link, its own choices, and its own groups — and any list can be duplicated, so you only set the books up once.</p>
    </div>
    <button class="button primary" onclick={() => (draft = { mode: "new", name: "", description: "" })}>
      + New book list
    </button>
  </section>

  {#if error}<p class="message error" role="alert">{error}</p>{/if}

  {#if draft}
    <form class="list-form" onsubmit={saveDraft}>
      <h2>
        {draft.mode === "new"
          ? "New book list"
          : draft.mode === "copy"
            ? `Duplicate “${draft.source?.name}”`
            : `Edit “${draft.source?.name}”`}
      </h2>
      {#if draft.mode === "copy" && draft.source}
        {@const copying = booksIn(draft.source.id).length}
        <p class="muted">
          The {copying} {copying === 1 ? "book" : "books"} in “{draft.source.name}” will be copied into this new list,
          ready for another group of students. Student choices and saved groups stay with the original.
        </p>
      {/if}
      <label>Name <input bind:value={draft.name} maxlength="60" required placeholder="e.g. 1st Period" /></label>
      <label>
        Description
        <textarea bind:value={draft.description} maxlength="300" rows="2" placeholder="A note to yourself about this class. Students never see it."></textarea>
      </label>
      <div class="button-row">
        <button class="button primary" disabled={busy}>
          {busy
            ? "Saving…"
            : draft.mode === "copy"
              ? "Duplicate list"
              : draft.mode === "edit"
                ? "Save changes"
                : "Create list"}
        </button>
        <button class="button text" type="button" onclick={() => (draft = undefined)}>Cancel</button>
      </div>
    </form>
  {/if}

  {#if loading}
    <div class="center-block"><div class="loader"></div></div>
  {:else if !lists.length}
    <div class="empty-state">
      <div class="empty-books">1&nbsp; 2&nbsp; 3&nbsp; 4</div>
      <h3>No book lists yet</h3>
      <p>Make one for your first class, then duplicate it for the rest.</p>
    </div>
  {:else}
    <section class="list-grid">
      {#each lists as list}
        {@const count = booksIn(list.id).length}
        {@const short = minimumBooks - count}
        <article class="list-card">
          <div class="list-card-head">
            <div>
              <h2><button class="list-title" onclick={() => navigate(`/list/${list.id}`)}>{list.name}</button></h2>
              <p class:list-no-note={!list.description}>{list.description || "No description"}</p>
            </div>
            {#if planned.includes(list.id)}<span class="saved-badge">Groups saved</span>{/if}
          </div>

          <dl class="list-stats">
            <div><dt>Books</dt><dd>{count}</dd></div>
            <div><dt>Student choices</dt><dd>{responsesIn(list.id)}</dd></div>
          </dl>

          {#if short <= 0}
            <div class="share-actions">
              <input value={studentLink(list)} readonly aria-label={`Student link for ${list.name}`} />
              <button class="button accent small" onclick={() => copyLink(list)}>{copiedId === list.id ? "Copied!" : "Copy link"}</button>
            </div>
          {:else}
            <p class="list-hint">{short} more {short === 1 ? "book" : "books"} before this list's student link opens.</p>
          {/if}

          <div class="list-card-actions">
            <button class="button primary small" onclick={() => navigate(`/list/${list.id}`)}>Open</button>
            <button
              class="button subtle small"
              disabled={busy || !count}
              title={count ? "Copy these books into a list for another class" : "Add books before duplicating this list"}
              onclick={() => (draft = { mode: "copy", source: list, name: `${list.name} copy`, description: list.description })}
            >
              Duplicate
            </button>
            <button class="text-link" onclick={() => (draft = { mode: "edit", source: list, name: list.name, description: list.description })}>
              Edit details
            </button>
            <button class="text-link danger" disabled={busy} onclick={() => remove(list)}>Delete</button>
          </div>
        </article>
      {/each}
    </section>
  {/if}
</main>
