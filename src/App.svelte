<script lang="ts">
  import { onMount } from "svelte";
  import Auth from "./Auth.svelte";
  import Dashboard from "./Dashboard.svelte";
  import StudentRanking from "./StudentRanking.svelte";
  import { pb } from "./lib";

  let ready = $state(false);
  let authenticated = $state(pb.authStore.isValid);
  const studentMatch = window.location.pathname.match(/^\/student\/([A-Za-z0-9_-]+)\/?$/);

  onMount(async () => {
    if (authenticated) {
      try {
        await pb.collection("teachers").authRefresh();
      } catch {
        pb.authStore.clear();
        authenticated = false;
      }
    }
    ready = true;
  });

  function signedIn() {
    authenticated = true;
  }

  function signedOut() {
    pb.authStore.clear();
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
