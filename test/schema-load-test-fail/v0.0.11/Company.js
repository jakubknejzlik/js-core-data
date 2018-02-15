const ManagedObject = require("../../../lib/ManagedObject");

class Company extends ManagedObject {
  customName() {
    return `${this.name}+custom`;
  }
}

module.exports = Company;
