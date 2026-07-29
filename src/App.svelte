<script lang="ts">
  import { onMount } from "svelte";
  import Auth from "./Auth.svelte";
  import BookListPage from "./BookListPage.svelte";
  import Dashboard from "./Dashboard.svelte";
  import StudentRanking from "./StudentRanking.svelte";
  import { navigate, supabase } from "./lib";

  let ready = $state(false);
  let authenticated = $state(false);
  let path = $state(window.location.pathname);

  // Three pages: a student's ranking form, the teacher's dashboard of book
  // lists, and one book list opened for editing.
  const studentToken = $derived(path.match(/^\/student\/([A-Za-z0-9_-]+)\/?$/)?.[1]);
  const openListId = $derived(path.match(/^\/list\/([0-9a-fA-F-]{36})\/?$/)?.[1]);

  onMount(() => {
    const followUrl = () => (path = window.location.pathname);
    window.addEventListener("popstate", followUrl);

    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      authenticated = Boolean(session);
      ready = true;
    });

    return () => {
      window.removeEventListener("popstate", followUrl);
      data.subscription.unsubscribe();
    };
  });

  function signedIn() {
    authenticated = true;
  }

  async function signedOut() {
    await supabase.auth.signOut();
    authenticated = false;
    navigate("/");
  }
</script>

{#if studentToken}
  <StudentRanking token={studentToken} />
{:else if !ready}
  <main class="center-page"><div class="loader" aria-label="Loading"></div></main>
{:else if !authenticated}
  <Auth onSignIn={signedIn} />
{:else if openListId}
  <BookListPage listId={openListId} onSignOut={signedOut} />
{:else}
  <Dashboard onSignOut={signedOut} />
{/if}
