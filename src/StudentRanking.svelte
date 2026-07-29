<script lang="ts">
  import { onMount } from "svelte";
  import { coverUrl, errorMessage, supabase, type Book } from "./lib";

  let { token }: { token: string } = $props();
  let books = $state<Book[]>([]);
  let teacher = $state("");
  let firstName = $state("");
  let lastInitial = $state("");
  let choices = $state<string[]>([]);
  let loading = $state(true);
  let busy = $state(false);
  let error = $state("");
  let submitted = $state(false);

  onMount(async () => {
    try {
      const { data, error: caught } = await supabase.rpc("student_view", { token });
      if (caught) throw caught;
      books = data.books;
      teacher = data.teacher;
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      loading = false;
    }
  });

  function select(bookId: string) {
    const current = choices.indexOf(bookId);
    if (current >= 0) choices = choices.filter((id) => id !== bookId);
    else if (choices.length < 4) choices = [...choices, bookId];
  }

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    error = "";
    if (choices.length !== 4) {
      error = "Choose and rank exactly four books.";
      return;
    }
    busy = true;
    try {
      const { error: caught } = await supabase.rpc("student_submit", {
        token,
        student_first_name: firstName,
        student_last_initial: lastInitial,
        book_choices: choices,
      });
      if (caught) throw caught;
      submitted = true;
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      busy = false;
    }
  }
</script>

<header class="student-header"><a class="brand brand-light" href="/"><span class="brand-mark">G</span><span>Group Readers</span></a></header>

{#if loading}
  <main class="center-page student-bg"><div class="loader light-loader"></div></main>
{:else if error && books.length === 0}
  <main class="center-page student-bg"><section class="student-error"><h1>We couldn’t open this book club.</h1><p>{error}</p><p>Ask your teacher to check the link and try again.</p></section></main>
{:else if submitted}
  <main class="center-page student-bg">
    <section class="success-card"><div class="success-check">✓</div><p class="eyebrow">Choices submitted</p><h1>Your reading voice is in!</h1><p>Your teacher can now see your ranked books. You can close this page, or submit again if you need to change your choices.</p><button class="button primary" onclick={() => (submitted = false)}>Change my choices</button></section>
  </main>
{:else}
  <main class="student-page">
    <section class="student-hero shell narrow">
      <p class="eyebrow light">{teacher}’s book club</p>
      <h1>Which stories are calling you?</h1>
      <p>Pick four books in order. The first book you tap is your #1 choice.</p>
      <div class="ranking-progress" aria-label={`${choices.length} of 4 books chosen`}>
        {#each [0, 1, 2, 3] as rank}<span class:filled={choices[rank]}>{choices[rank] ? rank + 1 : ""}</span>{/each}
        <strong>{choices.length === 4 ? "Ready to submit" : `${4 - choices.length} more to choose`}</strong>
      </div>
    </section>

    <form class="student-content shell narrow" onsubmit={submit}>
      <section class="name-card">
        <div><span class="step">1</span><div><h2>First, who are you?</h2><p>Only your teacher will see your name.</p></div></div>
        <label>First name <input bind:value={firstName} required maxlength="50" autocomplete="given-name" placeholder="Jordan" /></label>
        <label>Last initial <input class="initial-input" bind:value={lastInitial} required maxlength="1" autocapitalize="characters" placeholder="M" /></label>
      </section>

      <div class="section-title"><span class="step">2</span><div><h2>Now choose your top four</h2><p>Tap in order from your first choice to your fourth. Tap again to remove one.</p></div></div>
      <section class="student-books">
        {#each books as book}
          {@const rank = choices.indexOf(book.id)}
          <button type="button" class="choice-card" class:selected={rank >= 0} disabled={rank < 0 && choices.length === 4} onclick={() => select(book.id)}>
            {#if rank >= 0}<span class="rank-badge">#{rank + 1}</span>{/if}
            <img src={coverUrl(book)} alt="Cover of {book.title}" />
            <span class="choice-copy"><strong>{book.title}</strong><span>{book.blurb}</span></span>
            <span class="choose-action">{rank >= 0 ? "Chosen" : "Choose"}</span>
          </button>
        {/each}
      </section>
      {#if error}<p class="message error" role="alert">{error}</p>{/if}
      <div class="submit-bar"><div><strong>{choices.length}/4 chosen</strong><span>{choices.length === 4 ? "Your ranking is complete." : "Keep choosing in order."}</span></div><button class="button accent large" disabled={busy || choices.length !== 4}>{busy ? "Submitting…" : "Submit my choices"}</button></div>
    </form>
  </main>
{/if}
