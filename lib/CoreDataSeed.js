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

    let stream = await this._getStreamFromFile(filePath);
    let results = [];

    stream = stream.pipe(
      es.map(async (itemData, cb) => {
        try {
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
            if (record[i] != "") {
              object[columns[i]] = record[i];
            }
          }
          return object;
        }
      })
    );
  }
}

module.exports = CoreDataSeed;