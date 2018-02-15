const fs = require("fs");
const path = require("path");
const semver = require("semver");

const ManagedObject = require("./ManagedObject");

class CoreDataSchema {
  constructor(coredata) {
    this.coredata = coredata;
  }

  async load(schemaPath) {
    const database = this.coredata;
    let files = [];
    let folders = [];
    fs.readdirSync(schemaPath).forEach(item => {
      let stat = fs.statSync(path.join(schemaPath, item));
      if (stat.isDirectory()) {
        folders.push(item);
      } else {
        files.push(item);
      }
    });

    files = files.sort((a, b) => {
      return semver.gt(
        this._createModelVersionName(a),
        this._createModelVersionName(b)
      );
    });

    files.forEach(file => {
      const version = this._createModelVersionName(file);
      let model = database.createModelFromYaml(
        fs.readFileSync(path.join(schemaPath, file)),
        {},
        version
      );

      if (~folders.indexOf(model.version)) {
        this._loadClassesForModel(schemaPath, model);
      }
    });
    let latestVersion = this._createModelVersionName(files[files.length - 1]);
    database.setModelVersion(latestVersion);

    if (~folders.indexOf("latest")) {
      this._loadClassesForModel(schemaPath, database.model, "latest");
    }
  }

  _createModelVersionName(filePath) {
    return path.basename(filePath).replace(/\.ya?ml/, "");
  }

  _loadClassesForModel(schemaPath, model, version = null) {
    let classesFolder = path.join(schemaPath, version || model.version);

    let files = fs.readdirSync(classesFolder);
    for (let file of files) {
      let filename = path.join(classesFolder, file);
      let entityName = file.replace(path.extname(file), "");

      let entity = model.getEntity(entityName);
      if (!entity)
        throw new Error(
          `Entity ${entityName} not found for custom class at path ${filename}`
        );

      let customClass = require(filename);
      customClass = customClass.default || customClass;
      if (!(customClass.prototype instanceof ManagedObject))
        throw new Error(
          `Unable to load ${filename}, exported class isn't instance of ManagedObject`
        );

      entity.objectClass = customClass;
    }
  }
}

module.exports = CoreDataSchema;
