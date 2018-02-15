const ManagedObject = require("./../../lib/ManagedObject");

class Owner extends ManagedObject {
  getFullName() {
    return `${this.name} ${this.lastName}`;
  }
}

module.exports = Owner;
