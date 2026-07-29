<script lang="ts">
  import { downloadGroups } from "./export";
  import { createGroups, type GroupingResult, type GroupingSettings, type GroupingStrategy } from "./grouping";
  import { coverUrl, errorMessage, ordinal, supabase, type Book } from "./lib";

  let {
    books,
    submissions,
    savedPlan,
    listId,
    listName,
    rankedBooks,
    onSaved,
  }: {
    books: Book[];
    submissions: any[];
    savedPlan?: any;
    listId: string;
    listName: string;
    // How many books each of these students ranked, so the lowest rank a
    // placement can carry.
    rankedBooks: number;
    onSaved: () => void;
  } = $props();

  let minimumSize = $state(3);
  let maximumSize = $state(4);
  let strategy = $state<GroupingStrategy>("overall");
  let bookLimits = $state<Record<string, number>>({});
  let draft = $state<GroupingResult | undefined>();
  let draftIsSaved = $state(false);
  let saving = $state(false);
  let error = $state("");
  let initialized = false;

  $effect(() => {
    if (initialized) return;
    minimumSize = savedPlan?.settings?.minimumSize || 3;
    maximumSize = savedPlan?.settings?.maximumSize || 4;
    strategy = savedPlan?.settings?.strategy || "overall";
    bookLimits = Object.fromEntries(books.map((book) => [book.id, savedPlan?.settings?.bookLimits?.[book.id] ?? 1]));
    draft = savedPlan?.result;
    draftIsSaved = Boolean(savedPlan);
    initialized = true;
  });

  const strategyOptions = $derived<{ value: GroupingStrategy; title: string; description: string }[]>([
    { value: "overall", title: "Best overall fit", description: "Balances all preferences, scoring a first choice highest and each place below it lower." },
    { value: "first", title: "Maximize first choices", description: "Places as many students as possible into their first-choice book." },
    { value: "last", title: "Minimize last choices", description: `Avoids ${ordinal(rankedBooks)}-choice placements whenever another valid draft is possible.` },
  ]);

  function settings(): GroupingSettings {
    return { minimumSize, maximumSize, strategy, bookLimits: { ...bookLimits } };
  }

  function invalidateDraft() {
    draft = undefined;
    draftIsSaved = false;
  }

  function setAllLimits(value: number) {
    bookLimits = Object.fromEntries(books.map((book) => [book.id, value]));
    invalidateDraft();
  }

  function generate() {
    error = "";
    if (!Number.isInteger(minimumSize) || !Number.isInteger(maximumSize) || minimumSize < 2 || maximumSize > 12 || minimumSize > maximumSize) {
      error = "Choose a minimum of at least 2, and make sure the maximum is not smaller than the minimum.";
      return;
    }
    const students = submissions.map((submission) => ({
      id: submission.id,
      firstName: submission.firstName,
      lastInitial: submission.lastInitial,
      choices: submission.choices,
    }));
    draft = createGroups(books, students, settings(), rankedBooks);
    draftIsSaved = false;
  }

  async function save() {
    if (!draft) return;
    if (savedPlan && !confirm("Replace your previously confirmed groups with this draft?")) return;
    saving = true;
    error = "";
    try {
      const { error: caught } = await supabase.rpc("save_groups", {
        target_list: listId,
        plan_settings: settings(),
        plan_result: draft,
      });
      if (caught) throw caught;
      draftIsSaved = true;
      onSaved();
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      saving = false;
    }
  }

  function bookFor(bookId: string) {
    return books.find((book) => book.id === bookId)!;
  }
</script>

{#if submissions.length === 0}
  <div class="empty-state"><div class="empty-books">3&nbsp; 4</div><h3>Groups begin with student choices</h3><p>Once students rank their books, you can create balanced groups here.</p></div>
{:else}
  <section class="group-intro">
    <div><p class="eyebrow">Group settings</p><h2>Shape the groups your class needs.</h2><p>The best draft always places the greatest possible number of students before applying your preference strategy.</p></div>
    {#if savedPlan && draftIsSaved}<span class="saved-badge">Confirmed groups</span>{/if}
  </section>

  {#if error}<p class="message error" role="alert">{error}</p>{/if}

  <section class="group-settings">
    <div class="size-settings">
      <label>Minimum students per group <input type="number" min="2" max="12" bind:value={minimumSize} onchange={invalidateDraft} /></label>
      <label>Maximum students per group <input type="number" min="2" max="12" bind:value={maximumSize} onchange={invalidateDraft} /></label>
    </div>
    <fieldset class="strategy-settings">
      <legend>How should choices be optimized?</legend>
      {#each strategyOptions as option}
        <label class:chosen={strategy === option.value}><input type="radio" name="strategy" value={option.value} bind:group={strategy} onchange={invalidateDraft} /><span><strong>{option.title}</strong><small>{option.description}</small></span></label>
      {/each}
    </fieldset>
  </section>

  <section class="book-limits">
    <div class="section-row"><div><h3>Maximum groups per book</h3><p>Set a book to 0 to leave it out. A book may still receive no group when there is not a good fit.</p></div><button class="button subtle small" onclick={() => setAllLimits(1)}>Set all to 1</button></div>
    <div class="limit-grid">
      {#each books as book}
        <label class="limit-card"><img src={coverUrl(book)} alt="" /><span>{book.title}</span><input aria-label={`Maximum groups for ${book.title}`} type="number" min="0" max="5" bind:value={bookLimits[book.id]} onchange={invalidateDraft} /></label>
      {/each}
    </div>
  </section>

  <div class="generate-bar"><div><strong>{submissions.length} students ready</strong><span>Books without enough matching students will not form a group.</span></div><button class="button primary large" onclick={generate}>Generate best draft</button></div>

  {#if draft}
    <section class="group-results">
      <div class="results-head">
        <div><p class="eyebrow">{draftIsSaved ? "Confirmed result" : "Draft result"}</p><h2>{draft.placed} of {submissions.length} students placed</h2></div>
        <div class="result-actions">
          <button class="button subtle" onclick={() => downloadGroups(draft!, books, listName)}>Export spreadsheet</button>
          {#if !draftIsSaved}<button class="button accent" disabled={saving} onclick={save}>{saving ? "Saving…" : "Confirm and save groups"}</button>{/if}
        </div>
      </div>
      <p class="export-note">The spreadsheet opens in Excel or Google Sheets, one row per student, so you can move anybody between groups by hand.</p>
      <div class="placement-summary">
        {#each draft.rankCounts as count, index}<span><strong>{count}</strong>{ordinal(index + 1)} choice</span>{/each}
        <span class:attention={draft.unplaced.length > 0}><strong>{draft.unplaced.length}</strong>need help</span>
      </div>
      <div class="generated-groups">
        {#each draft.groups as group}
          {@const book = bookFor(group.bookId)}
          <article class="generated-group">
            <header><img src={coverUrl(book)} alt="" /><div><span>Group {group.groupNumber}</span><h3>{book.title}</h3></div><b>{group.members.length}</b></header>
            <ul>{#each group.members as member}<li><span>{member.firstName} {member.lastInitial}.</span><small class:last-rank={member.rank === rankedBooks}>{ordinal(member.rank)} choice</small></li>{/each}</ul>
          </article>
        {/each}
      </div>
      {#if draft.unplaced.length}
        <aside class="unplaced-card"><div><p class="eyebrow">Needs teacher placement</p><h3>{draft.unplaced.length} {draft.unplaced.length === 1 ? "student could" : "students could"} not fit</h3><p>Their ranked books could not form another valid group within these limits. Adjust the settings and regenerate, or place them manually.</p></div><ul>{#each draft.unplaced as student}<li>{student.firstName} {student.lastInitial}.</li>{/each}</ul></aside>
      {/if}
    </section>
  {/if}
{/if}
