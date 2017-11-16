const assert = require("assert");
const path = require("path");
const CoreData = require("../index");

var store_url = require("./get_storage_url");

var coreData = new CoreData(store_url, {
  logging: false
});

coreData.createModelFromYaml(
  fs.readFileSync(path.join(__dirname, "schemes/car-model.yaml")),
  { Car: require("./Classes/Car") }
);

const validateData = async () => {
  const context = coreData.createContext();

  let chuck = await context.getObjectWithId("Owner", 1);
  assert.ok(chuck);
  assert.equal(chuck.name, "Chuck");

  let chucksCars = await chuck.getCars();
  assert.equal(chucksCars.length, 2);

  let prius = await context.getObject("Car", { where: { uid: "prius" } });
  assert.ok(prius);

  let priusOwner = await prius.getOwner();
  assert.ok(priusOwner);
  assert.equal(priusOwner.name, "John Doe");

  context.destroy();
};

describe("Seed", function() {
  beforeEach(() => {
    return coreData.syncSchema({ force: true });
  });

  it("should import test seed data from json", async () => {
    await coreData.seed.run(path.join(__dirname, "seeds/json"));
    await validateData();
  });

  it("should import test seed data from csv", async () => {
    await coreData.seed.run(path.join(__dirname, "seeds/csv"));
    await validateData();
  });

  it("should fail to import invalid-entity", async () => {
    try {
      await coreData.seed.run(path.join(__dirname, "seeds/invalid-entity"));
      assert.fail("seed should not finish successfuly");
    } catch (e) {
      assert.equal(e.message, `entity with name 'Caar' doesn't exists`);
    }
  });
  it("should fail to import invalid-csv", async () => {
    try {
      await coreData.seed.run(path.join(__dirname, "seeds/invalid-csv"));
      assert.fail("seed should not finish successfuly");
    } catch (e) {
      assert.equal(
        e.message,
        `invalid data {"toyota":"ford","":"2"} for entity \'Car\'`
      );
    }
  });
});
