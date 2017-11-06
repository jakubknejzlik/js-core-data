const fs = require("fs");
const path = require("path");
_ = require("underscore");
_.mixin(require("underscore.inflections"));

class CoreDataSeed {
  constructor(coredata) {
    this.coredata = coredata;
  }

  async run(seedPath) {
    const db = this.coredata;
    const context = db.createContext();
    const files = fs.readdirSync(seedPath);

    let seedResults = {};
    for (let file of files) {
      seedResults[file] = await this._createEntitiesFromFile(
        context,
        path.join(seedPath, file)
      );
    }

    await context.save();

    for (let key in seedResults) {
      await this._updateRelationshipImportResults(seedResults[key]);
    }

    return context.saveAndDestroy();
  }

  async _createEntitiesFromFile(context, filePath) {
    const entityName = path
      .basename(filePath)
      .replace(path.extname(filePath), "");

    const data = require(filePath);

    if (!Array.isArray(data)) {
      throw new Error("data is not an array");
    }

    let results = [];
    for (let itemData of data) {
      let result = { data: itemData };
      if (itemData.id) {
        result.entity = await context.getOrCreateObject(
          entityName,
          { where: { id: itemData.id } },
          itemData
        );
      } else {
        result.entity = context.create(entityName, itemData);
      }
      results.push(result);
    }

    return results;
  }

  async _updateRelationshipImportResults(results) {
    for (let result of results) {
      const relationships = result.entity.entity.relationshipsByName();
      for (let key in relationships) {
        if (result.data[key]) {
          await this._updateRelationshipForEntity(
            result.entity,
            relationships[key],
            result.data[key]
          );
        }
      }
    }
  }

  async _updateRelationshipForEntity(entity, relationship, data) {
    if (relationship.toMany) {
      let setter = "add" + _.capitalize(relationship.name);
      let items = await entity.managedObjectContext.getObjects(
        relationship.destinationEntity.name,
        { where: { id: data } }
      );
      entity[setter](items);
    } else {
      let setter = "set" + _.capitalize(relationship.name);
      let item = await entity.managedObjectContext.getObjectWithId(
        relationship.destinationEntity.name,
        data
      );
      await entity[setter](item);
    }
  }
}

module.exports = CoreDataSeed;
