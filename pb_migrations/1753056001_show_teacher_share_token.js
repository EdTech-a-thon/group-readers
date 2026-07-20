migrate((app) => {
  const collection = app.findCollectionByNameOrId("teachers");
  collection.fields.getByName("shareToken").hidden = false;
  app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("teachers");
  collection.fields.getByName("shareToken").hidden = true;
  app.save(collection);
});
