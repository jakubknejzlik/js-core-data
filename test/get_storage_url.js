var storages = {
    mysql:'mysql://root@localhost/test',
    sqlite:'sqlite://:memory:?maxConnections=1'
}

module.exports = process.env.STORAGE_URL || storages[process.env.STORAGE || 'sqlite'];