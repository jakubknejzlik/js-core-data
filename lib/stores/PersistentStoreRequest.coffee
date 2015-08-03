class PersistentStoreRequest
  constructor:(@type)->

  insertedObjects:->
    []
  updatedObjects:->
    []
  deletedObjects:->
    []
  lockedObjects:->
    []


module.exports = PersistentStoreRequest