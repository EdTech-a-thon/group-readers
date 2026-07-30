<script lang="ts">
  import type { Snippet } from "svelte";
  import SiteFooter from "./SiteFooter.svelte";
  import { navigate } from "./lib";

  // The frame the About and Privacy pages share: a plain header, a heading, and
  // whatever sections that page wants to fill in.
  let { title, lede, children }: { title: string; lede: string; children: Snippet } = $props();

  function home(event: MouseEvent) {
    event.preventDefault();
    navigate("/");
  }
</script>

<header class="topbar">
  <a class="brand" href="/" onclick={home}>
    <span class="brand-mark">G</span><span>Group Readers</span>
  </a>
  <a class="text-link" href="/" onclick={home}>← Back to Group Readers</a>
</header>

<main class="info-page shell narrow">
  <h1>{title}</h1>
  <p class="info-lede">{lede}</p>
  {@render children()}
</main>

<SiteFooter />
