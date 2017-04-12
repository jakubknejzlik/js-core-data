// var storages = {
//     mysql:'mysql://root@localhost/test?',
//     sqlite:'sqlite://:memory:'
// }

module.exports = process.env.STORAGE_URL// || storages[process.env.STORAGE || 'sqlite'];
