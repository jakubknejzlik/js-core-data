var assert = require('assert'),
  ManagedObjectModel = require('./../lib/ManagedObjectModel'),
  ManagedObject = require('./../lib/ManagedObject'),
  ManagedObjectContext = require('./../lib/ManagedObjectContext'),
  ModelYamlParser = require('../lib/Parsers/ModelYamlParser');
PersistentStoreCoordinator = require('./../lib/PersistentStoreCoordinator');
var CoreData = require('../index');

var store_url = require('./get_storage_url');

var coreData = new CoreData(store_url, {
  logging: true
});
coreData.createModelFromYaml(
  fs.readFileSync(__dirname + '/schemes/cyclic-relationship.yaml')
);

describe('cyclic relationships', function() {
  var objectModel = new ManagedObjectModel();
  ModelYamlParser.fillModelFromYaml(
    objectModel,
    fs.readFileSync(__dirname + '/schemes/cyclic-relationship.yaml')
  );

  describe('parent class', function() {
    var storeCoordinator;
    before(function() {
      //storeCoordinator = new PersistentStoreCoordinator(objectModel);
      //storeCoordinator.addStore(store_url)
      //storeCoordinator.persistentStores[0].syncSchema({force:true},done);
      return coreData.syncSchema({ force: true }).then(() => {
        var context = coreData.createContext();
        var car = context.createObjectWithName('Car');
        car.name = 'car1';
        var user = context.createObjectWithName('User');
        user.name = 'user1';

        car.setOwner(user);
        user.setFavoriteCar(car);
        return context.save();
      });
    });
    it('should load all cars ', function(done) {
      var context = coreData.createContext();
      context.getObjects('Car', function(err, cars) {
        assert.ifError(err);
        assert.equal(cars.length, 1);
        done();
      });
    });
  });
});
