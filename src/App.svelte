<script lang="ts">
  import { onMount } from "svelte";
  import Auth from "./Auth.svelte";
  import Dashboard from "./Dashboard.svelte";
  import StudentRanking from "./StudentRanking.svelte";
  import { supabase } from "./lib";

  let ready = $state(false);
  let authenticated = $state(false);
  const studentMatch = window.location.pathname.match(/^\/student\/([A-Za-z0-9_-]+)\/?$/);

  onMount(() => {
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      authenticated = Boolean(session);
      ready = true;
    });
    return () => data.subscription.unsubscribe();
  });

  function signedIn() {
    authenticated = true;
  }

  async function signedOut() {
    await supabase.auth.signOut();
    authenticated = false;
  }
</script>

{#if studentMatch}
  <StudentRanking token={studentMatch[1]} />
{:else if !ready}
  <main class="center-page"><div class="loader" aria-label="Loading"></div></main>
{:else if authenticated}
  <Dashboard onSignOut={signedOut} />
{:else}
  <Auth onSignIn={signedIn} />
{/if}
