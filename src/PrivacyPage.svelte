<script lang="ts">
  import InfoPage from "./InfoPage.svelte";
</script>

<InfoPage title="Privacy" lede="What we store, what we don't, and why.">
  <section class="info-card">
    <h2>Students never sign up</h2>
    <p>
      A student opens their class's link, types their first name and last
      initial, puts books in order, and submits. That is everything Group Readers
      ever asks a student for. There is no account, no password, and no email
      address, and we never ask for a school ID, a birthday, or anything else
      about them.
    </p>
    <p>
      The name is there for one reason: so their teacher can tell whose choices
      are whose when they build the groups. Only that teacher can see it.
    </p>
  </section>

  <section class="info-card">
    <h2>What we store</h2>
    <p>
      Group Readers is a tool teachers save work in, so unlike a page you simply
      read, it does keep information. All of it is listed here.
    </p>
    <div class="table-wrap">
      <table>
        <thead>
          <tr><th>What</th><th>Why</th><th>Who can see it</th></tr>
        </thead>
        <tbody>
          <tr>
            <th>Teacher's email and password</th>
            <td>To sign a teacher in and back into their own book lists.</td>
            <td>Nobody else. Passwords are stored only as a hash.</td>
          </tr>
          <tr>
            <th>Teacher's display name</th>
            <td>It labels the ranking page, so students know whose book club they landed in.</td>
            <td>That teacher's students.</td>
          </tr>
          <tr>
            <th>Book lists and books</th>
            <td>Names, private notes, book titles, descriptions, and cover images.</td>
            <td>The teacher, and students given the list's link.</td>
          </tr>
          <tr>
            <th>Student responses</th>
            <td>A first name, a last initial, and that student's ranked books.</td>
            <td>Only the teacher who owns the list.</td>
          </tr>
          <tr>
            <th>Saved groups</th>
            <td>The groups a teacher generated, so they are still there next time.</td>
            <td>Only the teacher who owns the list.</td>
          </tr>
        </tbody>
      </table>
    </div>
    <p>
      Signing in also keeps a session in your browser so you stay signed in
      between visits. Signing out clears it.
    </p>
  </section>

  <section class="info-card">
    <h2>What we don't do</h2>
    <ul class="promise-list">
      <li>
        <span class="tick">✓</span>
        <div>
          <strong>No tracking or advertising.</strong>
          <span>
            We run no advertising and no third-party tracking scripts. The one
            thing we do measure is non-identifiable usage: Cloudflare Web Analytics
            anonymously counts visits, so we can tell how much Group Readers is
            being used in classrooms. It is cookieless, does not fingerprint
            visitors, and does not follow anyone across other sites — see
            Cloudflare's
            <a href="https://www.cloudflare.com/privacypolicy/" target="_blank" rel="noopener noreferrer">privacy policy</a>
            for details.
          </span>
        </div>
      </li>
      <li>
        <span class="tick">✓</span>
        <div>
          <strong>No selling or sharing.</strong>
          <span>
            We do not sell, share, or otherwise transfer teacher or student data
            to anyone. It is used to run Group Readers and nothing else.
          </span>
        </div>
      </li>
    </ul>
  </section>

  <section class="info-card">
    <h2>Good to know</h2>
    <p>
      A student link is unlisted rather than secret: anyone holding it can see
      that list's books and add a response, so share it with your class rather
      than posting it publicly. Cover images you upload are served from a public
      address too, so use book covers rather than photos of anything private.
    </p>
    <p>
      You stay in control of the rest. Clearing a list's responses deletes them,
      and deleting a book list deletes its books, its responses, and its saved
      groups for good. If you'd like your whole account and everything in it
      removed, email us and we'll take care of it.
    </p>
  </section>

  <section class="info-card">
    <h2>Questions or concerns?</h2>
    <p>Ask us anything about this page, or about the data we hold for your class.</p>
    <a class="button primary" href="mailto:support@groupreaders.com?subject=Group%20Readers%20privacy">
      Email support@groupreaders.com
    </a>
  </section>
</InfoPage>
