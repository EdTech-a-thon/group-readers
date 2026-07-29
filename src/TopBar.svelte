<script lang="ts">
  import { navigate } from "./lib";

  let { username, onSignOut }: { username: string; onSignOut: () => void } = $props();
</script>

<header class="topbar">
  <a
    class="brand"
    href="/"
    onclick={(event) => {
      event.preventDefault();
      navigate("/");
    }}
  >
    <span class="brand-mark">G</span><span>Group Readers</span>
  </a>
  <div class="teacher-menu">
    <span class="avatar">{username.slice(0, 1).toUpperCase()}</span>
    <span>{username}</span>
    <button class="text-link" onclick={onSignOut}>Sign out</button>
  </div>
</header>
