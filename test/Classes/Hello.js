const ManagedObject = require("./../../lib/ManagedObject");

class Hello extends ManagedObject {
  awakeFromInsert() {
    super.awakeFromInsert();
    this.awakeFromInsertValue = "awaken";
  }
  awakeFromFetch() {
    super.awakeFromFetch();
    this.awakeFromFetchValue = "fetched";
  }

  willSave() {
    this.saveValue = "will save";
  }
  didSave() {
    this.saveValue = "did save";
  }

  getFullName() {
    return `${this.firstname} ${this.lastname}`;
  }

  setFullName(fullName) {
    if (this.fullName === null) {
      this.firstname = null;
      this.lastname = null;
    } else {
      let parts = fullName.split(" ");
      this.firstname = parts[0];
      this.lastname = parts[1];
    }
  }

  getFullName2() {
    return `${this.firstname} ${this.lastname}`;
  }
}

module.exports = Hello;
