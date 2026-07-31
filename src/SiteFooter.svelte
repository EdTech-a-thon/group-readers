<script lang="ts">
  import { navigate } from "./lib";
  import logo from "./assets/logo.svg";

  // About and Privacy are ordinary pages of this app, so they open the same way
  // every other link here does rather than reloading the whole site.
  function open(event: MouseEvent, to: string) {
    event.preventDefault();
    navigate(to);
  }
</script>

<footer class="site-footer">
  <p class="footer-credit">
    <img class="edtech-logo small" src={logo} alt="" />
    <span>
      A free classroom tool from the
      <a href="https://edtechathon.com" target="_blank" rel="noopener noreferrer">EdTech-a-thon</a>.
    </span>
  </p>
  <nav>
    <a href="/about" onclick={(event) => open(event, "/about")}>About</a>
    <a href="/privacy" onclick={(event) => open(event, "/privacy")}>Privacy</a>
    <a href="mailto:support@groupreaders.com?subject=Group%20Readers%20Support">Support</a>
  </nav>
</footer>
