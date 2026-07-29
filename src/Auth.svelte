<script lang="ts">
  import { errorMessage, supabase } from "./lib";

  let { onSignIn }: { onSignIn: () => void } = $props();
  let mode: "signin" | "signup" = $state("signin");
  let email = $state("");
  let displayName = $state("");
  let password = $state("");
  let confirmPassword = $state("");
  let busy = $state(false);
  let error = $state("");

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    error = "";
    if (mode === "signup" && password !== confirmPassword) {
      error = "The passwords do not match.";
      return;
    }

    busy = true;
    try {
      const credentials = { email: email.trim(), password };
      const { data, error: caught } =
        mode === "signup"
          ? await supabase.auth.signUp({
              ...credentials,
              options: { data: { username: displayName.trim() } },
            })
          : await supabase.auth.signInWithPassword(credentials);

      if (caught) throw caught;
      if (!data.session) throw new Error("We could not sign you in. Please try again.");
      onSignIn();
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      busy = false;
    }
  }

  function switchMode(next: "signin" | "signup") {
    mode = next;
    error = "";
    password = "";
    confirmPassword = "";
  }
</script>

<main class="auth-page">
  <section class="auth-intro">
    <a class="brand brand-light" href="/" aria-label="Book Club Builder home">
      <span class="brand-mark">B</span>
      <span>Book Club Builder</span>
    </a>
    <div class="intro-copy">
      <p class="eyebrow light">Turn choice into community</p>
      <h1>Every great book club starts with a student’s voice.</h1>
      <p>Create your reading list, share one simple link, and see every student’s top choices together.</p>
    </div>
    <div class="book-stack" aria-hidden="true">
      <div class="book book-one">Imagine</div>
      <div class="book book-two">Wonder</div>
      <div class="book book-three">Belong</div>
    </div>
  </section>

  <section class="auth-panel">
    <div class="auth-card">
      <p class="eyebrow">Teacher workspace</p>
      <h2>{mode === "signin" ? "Welcome back" : "Create your account"}</h2>
      <p class="muted">
        {mode === "signin" ? "Sign in to manage your class book choices." : "Start building your class reading list."}
      </p>

      <div class="tabs" aria-label="Account options">
        <button class:active={mode === "signin"} onclick={() => switchMode("signin")}>Sign in</button>
        <button class:active={mode === "signup"} onclick={() => switchMode("signup")}>Create account</button>
      </div>

      <form onsubmit={submit}>
        <label>
          Email
          <input bind:value={email} type="email" autocomplete="email" required placeholder="you@school.org" />
        </label>
        {#if mode === "signup"}
          <label>
            Display name
            <input bind:value={displayName} autocomplete="name" minlength="3" maxlength="30" required placeholder="e.g. Ms Rivera" />
            <small class="field-hint">Your students see this name on their ranking page.</small>
          </label>
        {/if}
        <label>
          Password
          <input bind:value={password} type="password" autocomplete={mode === "signup" ? "new-password" : "current-password"} minlength="8" required placeholder="At least 8 characters" />
        </label>
        {#if mode === "signup"}
          <label>
            Confirm password
            <input bind:value={confirmPassword} type="password" autocomplete="new-password" minlength="8" required placeholder="Type your password again" />
          </label>
        {/if}
        {#if error}<p class="message error" role="alert">{error}</p>{/if}
        <button class="button primary full" disabled={busy}>
          {busy ? "Please wait…" : mode === "signin" ? "Sign in" : "Create my account"}
        </button>
      </form>
      <p class="fine-print">Your email is only used to sign you in. Students never need an account.</p>
    </div>
  </section>
</main>
