ManagedObject = require("./../../lib/ManagedObject");

class User extends ManagedObject {
  getFirstname() {
    return this._getFirstname();
  }

  getFullName() {
    return `${this.firstname} ${this.lastname}`;
  }

  setFullName(fullName) {
    let parts = fullName.split(" ");
    this.firstname = parts[0];
    this.lastname = parts[1];
  }
}

module.exports = User;
