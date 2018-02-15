const assert = require("assert");
const path = require("path");
const CoreData = require("../index");

var store_url = require("./get_storage_url");

describe("Schema", function() {
  var coreData = new CoreData(store_url, {
    logging: false
  });

  before(async () => {
    await coreData.schema.load(path.join(__dirname, "schema-load-test"));
  });

  it("should fail to load invalid schema from path", async () => {
    var coreData2 = new CoreData(store_url, {
      logging: false
    });
    try {
      await coreData2.schema.load(
        path.join(__dirname, "schema-load-test-fail")
      );
      assert.ok(false, `should fail to load`);
    } catch (err) {
      assert.equal(
        err.message.indexOf(
          "Entity Company2 not found for custom class at path"
        ),
        0
      );
    }
  });

  it("should load valid schema from path", async () => {
    assert.deepEqual(Object.keys(coreData.models), [
      "v0.0.1",
      "v0.0.2",
      "v0.0.11"
    ]);
    assert.equal(coreData.model.version, "v0.0.11");
  });

  it("should create company with custom class", async () => {
    let context = coreData.createContext();
    let company = context.create("Company", { name: "test" });

    assert.equal(company.customName(), "test+custom");
  });
});
