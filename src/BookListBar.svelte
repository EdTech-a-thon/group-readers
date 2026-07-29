<script lang="ts">
  import { bookListColumns, duplicateBookList, errorMessage, supabase, type Book, type BookList } from "./lib";

  let {
    lists,
    activeId,
    teacherId,
    books,
    onSwitch,
    onChanged,
  }: {
    lists: BookList[];
    activeId: string;
    teacherId: string;
    books: Book[];
    onSwitch: (listId: string) => void;
    onChanged: (nextId?: string) => Promise<void>;
  } = $props();

  let busy = $state(false);
  let error = $state("");

  const active = $derived(lists.find((list) => list.id === activeId));

  function suggestedName() {
    return `Class ${lists.length + 1}`;
  }

  // Every action follows the same shape: ask for a name or a confirmation, do
  // the work, then let the dashboard reload its lists and open the right one.
  async function run(work: () => Promise<string | undefined>) {
    busy = true;
    error = "";
    try {
      const nextId = await work();
      await onChanged(nextId);
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      busy = false;
    }
  }

  function create() {
    const name = prompt("Name this book list, so you know which class it is for.", suggestedName());
    if (!name?.trim()) return;
    run(async () => {
      const { data, error: caught } = await supabase
        .from("book_lists")
        .insert({ name: name.trim() })
        .select(bookListColumns)
        .single();
      if (caught) throw caught;
      return data!.id as string;
    });
  }

  function duplicate() {
    const current = active;
    if (!current) return;
    const name = prompt(
      `Copy the ${books.length} book${books.length === 1 ? "" : "s"} in “${current.name}” into a new list for another class. Name the new list:`,
      `${current.name} copy`,
    );
    if (!name?.trim()) return;
    run(async () => (await duplicateBookList(teacherId, name.trim(), books)).id);
  }

  function rename() {
    const current = active;
    if (!current) return;
    const name = prompt("Rename this book list.", current.name);
    if (!name?.trim() || name.trim() === current.name) return;
    run(async () => {
      const { error: caught } = await supabase
        .from("book_lists")
        .update({ name: name.trim() })
        .eq("id", current.id);
      if (caught) throw caught;
      return current.id;
    });
  }

  function remove() {
    const current = active;
    if (!current) return;
    if (lists.length === 1) {
      error = "This is your only book list, so it cannot be deleted. Rename it instead.";
      return;
    }
    if (!confirm(`Delete “${current.name}”, its books, and its student responses? This cannot be undone.`)) return;

    const doomed = current.id;
    run(async () => {
      // The books go when the list goes, but their cover images have to be
      // cleared out by hand.
      const { data: covers } = await supabase.from("books").select("cover").eq("list", doomed);
      const { error: caught } = await supabase.from("book_lists").delete().eq("id", doomed);
      if (caught) throw caught;

      const paths = (covers || []).map((row) => row.cover).filter(Boolean);
      if (paths.length) await supabase.storage.from("covers").remove(paths);
      return lists.find((list) => list.id !== doomed)?.id;
    });
  }
</script>

<nav class="list-bar" aria-label="Your book lists">
  <span class="list-bar-label">Book lists</span>
  <div class="list-chips">
    {#each lists as list}
      <button class="list-chip" class:active={list.id === activeId} disabled={busy} onclick={() => onSwitch(list.id)}>
        {list.name}
      </button>
    {/each}
  </div>
  <div class="list-bar-actions">
    <button class="button subtle small" disabled={busy} onclick={create}>+ New list</button>
    <button class="button subtle small" disabled={busy || !books.length} onclick={duplicate} title="Copy these books into a list for another class">
      Duplicate
    </button>
    <button class="text-link" disabled={busy} onclick={rename}>Rename</button>
    <button class="text-link danger" disabled={busy || lists.length === 1} onclick={remove}>Delete</button>
  </div>
</nav>

{#if error}<p class="message error" role="alert">{error}</p>{/if}
