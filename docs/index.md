# js-core-data


[![Build Status](https://travis-ci.org/jakubknejzlik/js-core-data.svg?branch=master)](https://travis-ci.org/jakubknejzlik/js-core-data)
[![NPM Version][npm-image]][npm-url]
[![NPM Downloads][downloads-image]][downloads-url]

[![dependencies][dependencies-image]][dependencies-url]
[![devdependencies][devdependencies-image]][devdependencies-url]

[npm-image]: https://img.shields.io/npm/v/js-core-data.svg
[npm-url]: https://npmjs.org/package/js-core-data
[downloads-image]: https://img.shields.io/npm/dm/js-core-data.svg
[downloads-url]: https://npmjs.org/package/js-core-data

[dependencies-image]:https://david-dm.org/jakubknejzlik/js-core-data.png
[dependencies-url]:https://david-dm.org/jakubknejzlik/js-core-data
[devdependencies-image]:https://david-dm.org/jakubknejzlik/js-core-data/dev-status.png
[devdependencies-url]:https://david-dm.org/jakubknejzlik/js-core-data#info=devDependencies

==============

CoreData is very powerful framework created by Apple for working with data. This module is heavily inspired by it's principles and simplifies usage by implementing methods to fit server environment. Providing easy interface for defining data model, version migration, working with entities and persisting data to persistent store.

Currently supported persistent stores: MySQL, PostgreSQL, SQLite

# Documentation

* [Getting started](getting-started.md)
* [Contexts](contexts.md)
* [Schema](schema.md)
* [Relationships](relationships.md)
* [Fetching](fetching.md)
* [Predicates](predicates.md)
* [Migrations](migrations.md)
* [Examples](examples.md)
* [Express middleware](express.md)