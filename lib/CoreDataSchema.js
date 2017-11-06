const fs = require("fs");
const path = require("path");
const semver = require("semver");

class CoreDataSchema {
  constructor(coredata) {
    this.coredata = coredata;
  }

  async load(schemaPath) {
    const database = this.coredata;
    let files = [];
    files = fs.readdirSync(schemaPath);

    files = files.sort((a, b) => {
      return semver.gt(
        this._createModelVersionName(a),
        this._createModelVersionName(b)
      );
    });

    files.forEach(file => {
      const version = this._createModelVersionName(file);
      database.createModelFromYaml(
        fs.readFileSync(path.join(schemaPath, file)),
        {},
        version
      );
    });
    let modelVersion = this._createModelVersionName(files[files.length - 1]);
    database.setModelVersion(modelVersion);
  }

  _createModelVersionName(filePath) {
    return path.basename(filePath).replace(/\.ya?ml/, "");
  }
}

module.exports = CoreDataSchema;
