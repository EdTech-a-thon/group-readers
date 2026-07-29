import { mount } from "svelte";
import App from "./App.svelte";
import "./app.css";

const target = document.getElementById("app")!;

if (!import.meta.env.VITE_SUPABASE_URL || !import.meta.env.VITE_SUPABASE_ANON_KEY) {
  target.innerHTML = `<main class="center-page"><section class="student-error">
    <h1>Almost there</h1>
    <p>This site still needs to be connected to its Supabase project.</p>
    <p>Copy <code>.env.example</code> to <code>.env</code>, fill in the two values from
    your Supabase project settings, then start the site again.</p>
  </section></main>`;
} else {
  mount(App, { target });
}
