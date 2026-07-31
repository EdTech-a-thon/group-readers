<script lang="ts">
  import InfoPage from "./InfoPage.svelte";
  import { navigate } from "./lib";
  import logo from "./assets/logo.svg";
  import participants from "./assets/2026participants.jpeg";
</script>

<InfoPage
  title="About"
  lede="Group Readers turns a class's book preferences into reading groups, so teachers can save time putting students into groups."
>
  <section class="info-card">
    <div class="card-heading">
      <img class="edtech-logo" src={logo} alt="" />
      <h2>From the EdTech-a-thon</h2>
    </div>
    <p>
      Group Readers is a project from the
      <a href="https://edtechathon.com" target="_blank" rel="noopener noreferrer">EdTech-a-thon</a>,
      a community of builders making free tools for classrooms. Learn more about
      who we are and what else we're building at
      <a href="https://edtechathon.com" target="_blank" rel="noopener noreferrer">edtechathon.com</a>.
    </p>
    <figure class="polaroid">
      <img src={participants} alt="Everyone who took part in the 2026 EdTech-a-thon." />
      <figcaption>The 2026 EdTech-a-thon</figcaption>
    </figure>
  </section>

  <section class="info-card">
    <h2>How it works</h2>
    <ol class="info-steps">
      <li>
        <span class="step">1</span>
        <div>
          <h3>Build a book list</h3>
          <p>
            Add a cover, a title, and a short description for each book, and
            choose how many of them every student ranks.
          </p>
        </div>
      </li>
      <li>
        <span class="step">2</span>
        <div>
          <h3>Share one link</h3>
          <p>
            Each list has its own unlisted student link. Students open it, put
            their favourites in order, and submit. No account, no password.
          </p>
        </div>
      </li>
      <li>
        <span class="step">3</span>
        <div>
          <h3>Make the groups</h3>
          <p>
            Set your group sizes, and Group Readers places students with a book
            they ranked highly. Save the groups, or export them as a spreadsheet.
          </p>
        </div>
      </li>
    </ol>
    <p>Keep a separate list for each class, and duplicate one to set up the next.</p>
  </section>

  <section class="info-card">
    <h2>Our promise</h2>
    <ul class="promise-list">
      <li>
        <span class="tick">✓</span>
        <div>
          <strong>Zero paywalls.</strong>
          <span>Every part of Group Readers is free for every teacher.</span>
        </div>
      </li>
      <li>
        <span class="tick">✓</span>
        <div>
          <strong>Zero ads.</strong>
          <span>No advertising, and no ad networks anywhere on the site.</span>
        </div>
      </li>
      <li>
        <span class="tick">✓</span>
        <div>
          <strong>Zero tracking.</strong>
          <span>
            No third-party trackers, and nothing about your students is sold or
            shared. We count visits anonymously and that is all. See our
            <a
              href="/privacy"
              onclick={(event) => {
                event.preventDefault();
                navigate("/privacy");
              }}>privacy page</a
            > for exactly what is stored.
          </span>
        </div>
      </li>
    </ul>
  </section>

  <section class="info-card">
    <h2>Feedback &amp; ideas</h2>
    <p>
      We'd love to hear from you. Tell us what's working, what's not, or pitch us
      an idea for a tool you wish existed. We're here to help.
    </p>
    <a class="button primary" href="mailto:support@groupreaders.com?subject=Group%20Readers%20feedback">
      Email support@groupreaders.com
    </a>
  </section>
</InfoPage>
