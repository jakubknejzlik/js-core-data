const ManagedObject = require("./../../lib/ManagedObject");

class Car extends ManagedObject {
  setBrand(brand) {
    this._setBrand(brand);
  }
  setBrandCustom(value) {
    this.brand = value + value;
  }

  getOwnerCustom(callback) {
    this.getOwner(callback);
  }
}

module.exports = Car;
// // Generated by CoffeeScript 1.10.0
// (function() {
//   var Car, ManagedObject,
//     extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
//     hasProp = {}.hasOwnProperty;

//   ManagedObject = require('./../../lib/ManagedObject');

//   Car = (function(superClass) {
//     extend(Car, superClass);

//     function Car() {
//       Car.__super__.constructor.apply(this, arguments);
//     }

//     Car.prototype.setBrand = function(value) {
//       return this._setBrand(value);
//     };

//     Car.prototype.setBrandCustom = function(value) {
//       return this.brand = value + value;
//     };

//     Car.prototype.getOwnerCustom = function(callback) {
//       return this.getOwner(callback);
//     };

//     return Car;

//   })(ManagedObject);

//   module.exports = Car;

// }).call(this);
