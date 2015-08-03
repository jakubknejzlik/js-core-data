PersistentStore = require('./PersistentStore')
PersistentStoreRequest = require('./PersistentStoreRequest')
IncrementalStoreNode = require('./IncrementalStoreNode')

class IncrementalStore extends PersistentStore
  @getType:->
    'IncrementalStore'

# Fetch: retrieve the unique identifiers for every object of the specified entity type from your backing data store,
# create managed object IDs from those identifiers, and ask the context for managed objects with those object IDs.
# Add all of the managed objects to an array and return the array.
# row values can be cached and returned in valuesForObject method
  execute:(request,context,callback) ->
    if request not instanceof  PersistentStoreRequest
      throw new Error('request ' + request + ' is not instance of PersistentStoreRequest')
    throw new Error('execute method not implemented')

# The returned node should include all attributes values and may include to-one relationship values as instances of ManagedObjectID
  valuesForObject:(ObjectID,context) ->
    throw new Error('valuesForObjet method not implemented')

# If the relationship is a to-one, the method should return an NSManagedObjectID instance that identifies the destination, or an instance of NSNull if the relationship value is nil.
# If the relationship is a to-many, the method should return a collection object containing NSManagedObjectID instances to identify the related objects. Using an NSArray instance is preferred because it will be the most efficient. A store may also return an instance of NSSet or NSOrderedSet; an instance of NSDictionary is not acceptable.
# If an object with object ID objectID cannot be found, the method should return nil and—if error is not NULL—create and return an appropriate error object in error.
  valueForRelationship:(relationship,ObjectID,context,callback) ->
    throw new Error('valuesForObjet method not implemented')


# This method is called before executeRequest:withContext:error: with a save request, to assign permanent IDs to newly-inserted objects.
  permanentIDsForObjects:(objects,callback) ->
    throw new Error('permanentIDsForObjects method not implemented')

  newObjectID:(entity,referenceObject) ->

module.exports = IncrementalStore