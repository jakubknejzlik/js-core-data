var storages = {
    mysql:'mysql://root@localhost/test',
    sqlite:'sqlite://:memory:'
}
module.exports = storages[process.env.STORAGE || 'sqlite'];