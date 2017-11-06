const assert = require("assert");
const path = require("path");
const CoreData = require("../index");

var store_url = require("./get_storage_url");

var coreData = new CoreData(store_url, {
  logging: false
});

describe("Schema", function() {
  it("should load schema from path", async () => {
    await coreData.schema.load(path.join(__dirname, "schema-load-test"));

    assert.deepEqual(Object.keys(coreData.models), [
      "v0.0.1",
      "v0.0.2",
      "v0.0.11"
    ]);
    assert.equal(coreData.model.version, "v0.0.11");
  });
});
