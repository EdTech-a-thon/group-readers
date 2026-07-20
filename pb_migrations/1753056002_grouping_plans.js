migrate((app) => {
  const teachers = app.findCollectionByNameOrId("teachers");
  const plans = new Collection({
    type: "base",
    name: "grouping_plans",
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
      { type: "json", name: "settings", required: true, maxSize: 50000 },
      { type: "json", name: "result", required: true, maxSize: 200000 },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_grouping_plans_teacher ON grouping_plans (teacher)"],
  });
  app.save(plans);
}, (app) => {
  try {
    app.delete(app.findCollectionByNameOrId("grouping_plans"));
  } catch (_) {}
});
