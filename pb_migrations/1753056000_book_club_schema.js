migrate((app) => {
  const teachers = new Collection({
    type: "auth",
    name: "teachers",
    listRule: "id = @request.auth.id",
    viewRule: "id = @request.auth.id",
    createRule: "",
    updateRule: "id = @request.auth.id && @request.body.shareToken:changed = false",
    deleteRule: "id = @request.auth.id",
    fields: [
      {
        type: "text",
        name: "username",
        required: true,
        min: 3,
        max: 30,
        pattern: "^[a-zA-Z0-9._-]+$",
        presentable: true,
      },
      {
        type: "text",
        name: "shareToken",
        required: false,
        min: 24,
        max: 64,
        hidden: false,
      },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_teachers_username ON teachers (username)"],
    passwordAuth: {
      enabled: true,
      identityFields: ["username"],
    },
  });
  app.save(teachers);
  teachers.indexes = [
    "CREATE UNIQUE INDEX idx_teachers_username ON teachers (username)",
    "CREATE UNIQUE INDEX idx_teachers_share_token ON teachers (shareToken)",
  ];
  app.save(teachers);

  const books = new Collection({
    type: "base",
    name: "books",
    listRule: "teacher = @request.auth.id",
    viewRule: "teacher = @request.auth.id",
    createRule: "teacher = @request.auth.id",
    updateRule: "teacher = @request.auth.id && @request.body.teacher:changed = false",
    deleteRule: "teacher = @request.auth.id",
    fields: [
      {
        type: "relation",
        name: "teacher",
        required: true,
        maxSelect: 1,
        collectionId: teachers.id,
        cascadeDelete: true,
      },
      { type: "number", name: "position", required: true, min: 1, max: 10 },
      { type: "text", name: "title", required: true, min: 1, max: 120 },
      { type: "text", name: "blurb", required: true, min: 1, max: 500 },
      {
        type: "file",
        name: "cover",
        required: true,
        maxSelect: 1,
        maxSize: 5242880,
        mimeTypes: ["image/jpeg", "image/png", "image/webp", "image/gif"],
        thumbs: ["240x360"],
      },
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_books_teacher_position ON books (teacher, position)",
    ],
  });
  app.save(books);

  const submissions = new Collection({
    type: "base",
    name: "submissions",
    listRule: "teacher = @request.auth.id",
    viewRule: "teacher = @request.auth.id",
    fields: [
      {
        type: "relation",
        name: "teacher",
        required: true,
        maxSelect: 1,
        collectionId: teachers.id,
        cascadeDelete: true,
      },
      { type: "text", name: "firstName", required: true, min: 1, max: 50 },
      { type: "text", name: "lastInitial", required: true, min: 1, max: 1 },
      { type: "text", name: "studentKey", required: true, min: 3, max: 60, hidden: true },
      {
        type: "relation",
        name: "choices",
        required: true,
        minSelect: 4,
        maxSelect: 4,
        collectionId: books.id,
      },
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_submissions_student ON submissions (teacher, studentKey)",
    ],
  });
  app.save(submissions);

  const settings = app.settings();
  settings.meta.appName = "Book Club Builder";
  settings.meta.appURL = "https://book-club-groups.edtechathon.com";
  app.save(settings);
}, (app) => {
  for (const name of ["submissions", "books", "teachers"]) {
    try {
      app.delete(app.findCollectionByNameOrId(name));
    } catch (_) {}
  }
});
