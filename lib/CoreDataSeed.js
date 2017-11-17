const fs = require("fs");
const path = require("path");
const JSONStream = require("JSONStream");
const csv = require("csv");
const es = require("event-stream");
const streamtopromise = require("stream-to-promise");
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
      console.log(`seeding file ${file}`);
      let filePath = path.join(seedPath, file);
      seedResults[file] = await this._createEntitiesFromFile(context, filePath);
    }

    await context.save();

    for (let key in seedResults) {
      console.log(`updating relationships for file ${key}`);
      await this._updateRelationshipImportResults(seedResults[key]);
    }

    console.log(`saving context`);
    return context.saveAndDestroy();
  }

  async _createEntitiesFromFile(context, filePath) {
    const entityName = path
      .basename(filePath)
      .replace(path.extname(filePath), "");

    let stream = await this._getStreamFromFile(filePath);
    let results = [];
    let dataValidationChecked = false;

    stream = stream.pipe(
      es.map(async (itemData, cb) => {
        try {
          let result = { data: itemData };

          if (!dataValidationChecked) {
            let entity = context.storeCoordinator.objectModel.getEntity(
              entityName
            );
            if (!entity) {
              throw new Error(
                `entity with name '${entityName}' doesn't exists`
              );
            }
            if (!this._validateDataForEntity(entity, itemData)) {
              throw new Error(
                `invalid data ${JSON.stringify(
                  itemData
                )} for entity '${entityName}'`
              );
            }
            dataValidationChecked = true;
          }

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
          cb();
        } catch (e) {
          cb(e);
        }
      })
    );

    await streamtopromise(stream);

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
      if (typeof data === "string") {
        data = data.split(",");
      }
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

  async _getStreamFromFile(filePath) {
    const extension = path.extname(filePath);
    const stream = fs.createReadStream(filePath);
    switch (extension) {
      case ".json":
        return stream.pipe(JSONStream.parse("*"));
      case ".csv":
        return this._pipeCSV(stream);
    }
  }

  async _pipeCSV(stream) {
    let columns = null;

    return stream.pipe(csv.parse()).pipe(
      csv.transform(record => {
        if (!columns) {
          columns = record;
          return null;
        } else {
          let object = {};
          for (let i in columns) {
            if (record[i] == "NULL") {
              object[columns[i]] = null;
            } else if (record[i] != "") {
              object[columns[i]] = record[i];
            }
          }
          return object;
        }
      })
    );
  }

  _validateDataForEntity(entity, data) {
    for (let key in data) {
      if (entity.hasAttribute(key)) {
        return true;
      }
    }
    return false;
  }
}

module.exports = CoreDataSeed;
