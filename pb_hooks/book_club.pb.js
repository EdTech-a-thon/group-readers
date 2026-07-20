onRecordCreateRequest((e) => {
  const username = e.record.getString("username").trim().toLowerCase();
  e.record.set("username", username);
  e.record.set("email", username + "." + $security.randomString(12).toLowerCase() + "@teachers.bookclub.local");
  if (!e.record.getString("shareToken")) {
    e.record.set("shareToken", $security.randomString(40));
  }
  e.next();
}, "teachers");

onRecordEnrich((e) => {
  if (e.auth && (e.auth.id === e.record.id || e.hasSuperuserAuth())) {
    e.record.unhide("shareToken");
  }
  e.next();
}, "teachers");

routerAdd("GET", "/api/bookclub/student/{token}", (e) => {
  const token = e.request.pathValue("token");
  if (!token || token.length < 24) throw new NotFoundError("This book club link is not valid.");
  const teacher = e.app.findFirstRecordByFilter("teachers", "shareToken = {:token}", { token });
  const books = e.app.findRecordsByFilter(
    "books",
    "teacher = {:teacher}",
    "position",
    10,
    0,
    { teacher: teacher.id },
  );

  if (books.length !== 10) {
    throw new BadRequestError("This book club is not ready yet.");
  }

  return e.json(200, {
    teacher: teacher.getString("username"),
    books: books.map((book) => ({
      id: book.id,
      position: book.getInt("position"),
      title: book.getString("title"),
      blurb: book.getString("blurb"),
      cover: book.getString("cover"),
    })),
  });
});

routerAdd("POST", "/api/bookclub/student/{token}", (e) => {
  const token = e.request.pathValue("token");
  if (!token || token.length < 24) throw new NotFoundError("This book club link is not valid.");
  const teacher = e.app.findFirstRecordByFilter("teachers", "shareToken = {:token}", { token });
  const body = e.requestInfo().body;
  const firstName = String(body.firstName || "").trim().replace(/\s+/g, " ");
  const lastInitial = String(body.lastInitial || "").trim().replace(/\s+/g, " ").slice(0, 1).toUpperCase();
  const choices = Array.isArray(body.choices) ? body.choices : [];

  if (!/^[A-Za-z][A-Za-z '-]{0,48}[A-Za-z]$|^[A-Za-z]$/.test(firstName)) {
    throw new BadRequestError("Enter a valid first name.");
  }
  if (!/^[A-Z]$/.test(lastInitial)) {
    throw new BadRequestError("Enter one letter for the last initial.");
  }
  if (choices.length !== 4 || new Set(choices).size !== 4) {
    throw new BadRequestError("Choose four different books.");
  }

  const books = e.app.findRecordsByIds("books", choices);
  if (books.length !== 4 || books.some((book) => book.getString("teacher") !== teacher.id)) {
    throw new BadRequestError("One or more selected books are not available.");
  }

  const studentKey = firstName.toLowerCase() + "|" + lastInitial.toLowerCase();
  let submission;
  try {
    submission = e.app.findFirstRecordByFilter(
      "submissions",
      "teacher = {:teacher} && studentKey = {:key}",
      { teacher: teacher.id, key: studentKey },
    );
  } catch (_) {
    submission = new Record(e.app.findCollectionByNameOrId("submissions"));
    submission.set("teacher", teacher.id);
    submission.set("studentKey", studentKey);
  }

  submission.set("firstName", firstName.charAt(0).toUpperCase() + firstName.slice(1));
  submission.set("lastInitial", lastInitial);
  submission.set("choices", choices);
  e.app.save(submission);

  try {
    const plan = e.app.findFirstRecordByFilter("grouping_plans", "teacher = {:teacher}", { teacher: teacher.id });
    e.app.delete(plan);
  } catch (_) {}

  return e.json(200, { success: true });
});

routerAdd("POST", "/api/bookclub/clear", (e) => {
  const submissions = e.app.findRecordsByFilter(
    "submissions",
    "teacher = {:teacher}",
    "",
    0,
    0,
    { teacher: e.auth.id },
  );
  e.app.runInTransaction((tx) => {
    for (const submission of submissions) tx.delete(submission);
    try {
      const plan = tx.findFirstRecordByFilter("grouping_plans", "teacher = {:teacher}", { teacher: e.auth.id });
      tx.delete(plan);
    } catch (_) {}
  });
  return e.json(200, { success: true });
}, $apis.requireAuth("teachers"));

routerAdd("POST", "/api/bookclub/groups", (e) => {
  const body = e.requestInfo().body;
  const settings = body.settings || {};
  const result = body.result || {};
  const minimum = Number(settings.minimumSize);
  const maximum = Number(settings.maximumSize);
  const strategies = ["overall", "first", "last"];
  if (!Number.isInteger(minimum) || !Number.isInteger(maximum) || minimum < 2 || maximum > 12 || minimum > maximum) {
    throw new BadRequestError("Choose valid minimum and maximum group sizes.");
  }
  if (!strategies.includes(settings.strategy) || !settings.bookLimits || !Array.isArray(result.groups) || !Array.isArray(result.unplaced)) {
    throw new BadRequestError("The grouping draft is not valid.");
  }

  const submissions = e.app.findRecordsByFilter("submissions", "teacher = {:teacher}", "", 0, 0, { teacher: e.auth.id });
  const books = e.app.findRecordsByFilter("books", "teacher = {:teacher}", "", 0, 0, { teacher: e.auth.id });
  const submissionIds = new Set(submissions.map((record) => record.id));
  const bookIds = new Set(books.map((record) => record.id));
  const assignedIds = [];
  const groupsPerBook = {};

  for (const book of books) {
    const limit = Number(settings.bookLimits[book.id] || 0);
    if (!Number.isInteger(limit) || limit < 0 || limit > 5) {
      throw new BadRequestError("Choose a valid maximum number of groups for each book.");
    }
  }

  for (const group of result.groups) {
    if (!bookIds.has(group.bookId) || !Array.isArray(group.members) || group.members.length < minimum || group.members.length > maximum) {
      throw new BadRequestError("One or more groups do not meet the selected limits.");
    }
    groupsPerBook[group.bookId] = (groupsPerBook[group.bookId] || 0) + 1;
    if (groupsPerBook[group.bookId] > Number(settings.bookLimits[group.bookId] || 0)) {
      throw new BadRequestError("A book has more groups than its selected limit.");
    }
    for (const member of group.members) {
      const submission = submissions.find((record) => record.id === member.id);
      const choices = submission && submission.get("choices");
      if (!submission || !choices.includes(group.bookId) || choices.indexOf(group.bookId) + 1 !== member.rank) {
        throw new BadRequestError("One or more student placements are not valid.");
      }
      assignedIds.push(member.id);
    }
  }
  for (const student of result.unplaced) assignedIds.push(student.id);
  if (assignedIds.length !== submissionIds.size || new Set(assignedIds).size !== submissionIds.size || assignedIds.some((id) => !submissionIds.has(id))) {
    throw new BadRequestError("Every student must appear exactly once in the grouping draft.");
  }

  let plan;
  try {
    plan = e.app.findFirstRecordByFilter("grouping_plans", "teacher = {:teacher}", { teacher: e.auth.id });
  } catch (_) {
    plan = new Record(e.app.findCollectionByNameOrId("grouping_plans"));
    plan.set("teacher", e.auth.id);
  }
  plan.set("settings", settings);
  plan.set("result", result);
  e.app.save(plan);
  return e.json(200, { success: true });
}, $apis.requireAuth("teachers"));

function protectLockedBooks(e) {
  if (e.hasSuperuserAuth()) return e.next();
  const teacherId = e.record.getString("teacher");
  const count = e.app.countRecords("submissions", $dbx.hashExp({ teacher: teacherId }));
  if (count > 0) {
    throw new BadRequestError("Clear student responses before changing the book list.");
  }
  if (e.record.isNew()) {
    const bookCount = e.app.countRecords("books", $dbx.hashExp({ teacher: teacherId }));
    if (bookCount >= 10) throw new BadRequestError("A book club can have only ten books.");
  }
  return e.next();
}

onRecordCreateRequest(protectLockedBooks, "books");
onRecordUpdateRequest(protectLockedBooks, "books");
onRecordDeleteRequest(protectLockedBooks, "books");
