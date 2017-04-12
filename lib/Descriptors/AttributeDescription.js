var AttributeDescription, AttributeType, PropertyDescription, attributeTypes, emailRegexp, floatTransform, floatValidate, integerTransform, integerValidate, moment, urlRegexp, uuid,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty,
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

PropertyDescription = require('./PropertyDescription');

AttributeType = require('./AttributeType');

moment = require('moment');

uuid = require('uuid');

attributeTypes = {};

AttributeDescription = (function(superClass) {
  extend(AttributeDescription, superClass);

  function AttributeDescription(type1, info, name, entity) {
    this.type = type1;
    this.info = info;
    this.persistentType = this.getAttributeType(this.info.persistentType || this.type).persistentStoreType;
    AttributeDescription.__super__.constructor.call(this, name, entity);
  }

  AttributeDescription.registerType = function(type, aliases) {
    var alias, i, len, results;
    if (aliases == null) {
      aliases = [];
    }
    attributeTypes[type.name] = type;
    results = [];
    for (i = 0, len = aliases.length; i < len; i++) {
      alias = aliases[i];
      results.push(attributeTypes[alias] = type);
    }
    return results;
  };

  AttributeDescription.prototype.getAttributeType = function() {
    if (!attributeTypes[this.type]) {
      throw new Error('unknown attribute type \'' + this.type + '\'');
    }
    return attributeTypes[this.type];
  };

  AttributeDescription.prototype.transform = function(value) {
    if (value === null) {
      return null;
    }
    return this.getAttributeType().transform(value, this);
  };

  AttributeDescription.prototype.decode = function(value) {
    return this.getAttributeType().decode(value, this);
  };

  AttributeDescription.prototype.encode = function(value) {
    if (value === null) {
      return null;
    }
    return this.getAttributeType().encode(value, this);
  };

  AttributeDescription.prototype.defaultValue = function() {
    var ref, value;
    value = (ref = this.info) != null ? ref["default"] : void 0;
    if (typeof value === 'undefined') {
      value = null;
    }
    return this.transform(value);
  };

  AttributeDescription.prototype.isPrivate = function() {
    return !!this.info["private"];
  };

  AttributeDescription.prototype.isTransient = function() {
    return !!this.info.transient;
  };

  AttributeDescription.prototype.validateValue = function(value) {
    if (value === null) {
      return;
    }
    if (!this.getAttributeType().validate(value, this)) {
      throw new Error('value \'' + value + '\' (' + (typeof value) + ') is not valid for attribute ' + this.name);
    }
  };

  AttributeDescription.prototype.toString = function() {
    return this.name + '(' + this.type + ')';
  };

  return AttributeDescription;

})(PropertyDescription);

module.exports = AttributeDescription;

urlRegexp = new RegExp('^(ht|f)tp(s?)\:\/\/(([a-zA-Z0-9\-\._]+(\.[a-zA-Z0-9\-\._]+)+)|localhost)(\/?)([a-zA-Z0-9\-\.\?\,\'\/\\\+&amp;%\$#_]*)?([\d\w\.\/\%\+\-\=\&amp;\?\:\\\&quot;\'\,\|\~\;]*)$');

emailRegexp = new RegExp('^[0-9a-zA-Z]+([0-9a-zA-Z]*[-._+])*[0-9a-zA-Z]+@[0-9a-zA-Z]+([-.][0-9a-zA-Z]+)*([0-9a-zA-Z]*[.])[a-zA-Z]{2,6}$');

floatTransform = function(value) {
  value = parseFloat(value);
  if (isNaN(value)) {
    value = null;
  }
  return value;
};

floatValidate = function(value, attribute) {
  var float;
  float = parseFloat(value);
  if (attribute.info.max && float > attribute.info.max) {
    throw new Error('value \'' + value + '\' larger than max(' + attribute.info.max + ') of attribute ' + attribute.name);
  }
  if (attribute.info.min && float < attribute.info.min) {
    throw new Error('value \'' + value + '\' smaller than min(' + attribute.info.min + ') of attribute ' + attribute.name);
  }
  if (!isNaN(parseFloat(value)) && isFinite(value)) {
    return true;
  }
};

integerTransform = function(value) {
  value = parseInt(value, 10);
  if (isNaN(value)) {
    value = null;
  }
  return value;
};

integerValidate = function(value, attribute) {
  var int;
  int = parseInt(value);
  if (attribute.info.max && int > attribute.info.max) {
    throw new Error('value \'' + value + '\' larger than max(' + attribute.info.max + ') of attribute ' + attribute.name);
  }
  if (attribute.info.min && int < attribute.info.min) {
    throw new Error('value \'' + value + '\' smaller than min(' + attribute.info.min + ') of attribute ' + attribute.name);
  }
  if (!isNaN(parseInt(value)) && isFinite(value) && parseInt(value, 10) === parseFloat(value)) {
    return true;
  }
};

AttributeDescription.registerType((new AttributeType('string', 'string')).validateFn(function(value, attribute) {
  var _re, v;
  if (attribute.info.maxLength && value.toString().length > attribute.info.maxLength) {
    throw new Error('value \'' + value + '\' larger than maxLength(' + attribute.info.maxLength + ') of attribute ' + attribute.name);
  }
  if (attribute.info.minLength && value.toString().length < attribute.info.minLength) {
    throw new Error('value \'' + value + '\' shorter than minLength(' + attribute.info.minLength + ') of attribute ' + attribute.name);
  }
  if (attribute.info.regexp) {
    if (!attribute.info._regexp) {
      v = attribute.info.regexp;
      _re = [];
      if (v[0] === '/') {
        v = v.substring(1);
        _re = v.split('/');
      } else {
        _re.push(v);
      }
      attribute.info._regexp = new RegExp(_re[0], _re[1]);
    }
    if (!attribute.info._regexp.test(value.toString())) {
      throw new Error('value \'' + value + '\' does is not valid for regular expression(' + attribute.info.regexp + ') of attribute ' + attribute.name);
    }
  }
  return true;
}));

AttributeDescription.registerType((new AttributeType('url', 'string')).validateFn(function(value, attribute) {
  if (urlRegexp.test(value)) {
    return true;
  }
}));

AttributeDescription.registerType((new AttributeType('email', 'string')).validateFn(function(value, attribute) {
  if (emailRegexp.test(value)) {
    return true;
  }
}));

AttributeDescription.registerType(new AttributeType('text', 'text'));

AttributeDescription.registerType(new AttributeType('data', 'data'));

AttributeDescription.registerType((new AttributeType('decimal', 'decimal')).transformFn(floatTransform).validateFn(floatValidate));

AttributeDescription.registerType((new AttributeType('float', 'float')).transformFn(floatTransform).validateFn(floatValidate));

AttributeDescription.registerType((new AttributeType('double', 'double')).transformFn(floatTransform).validateFn(floatValidate));

AttributeDescription.registerType((new AttributeType('integer', 'integer')).transformFn(integerTransform).validateFn(integerValidate), ['int']);

AttributeDescription.registerType((new AttributeType('bigint', 'bigint')).transformFn(integerTransform).validateFn(integerValidate));

AttributeDescription.registerType((new AttributeType('date', 'date')).transformFn(function(value, attribute) {
  if (value === null) {
    return null;
  }
  if (value === 'now') {
    value = new Date();
  }
  return moment(value).toDate();
}).validateFn(function(value) {
  if (value === 'now') {
    return true;
  }
  if (value instanceof Date || (typeof value === 'string' && moment(new Date(value)).isValid())) {
    return true;
  }
}).encodeFn(function(value) {
  if (value === null) {
    return null;
  }
  return moment(value).toISOString();
}).decodeFn(function(value) {
  if (value === null) {
    return null;
  }
  return moment.utc(value).toDate();
}));

AttributeDescription.registerType((new AttributeType('timestamp', 'timestamp')).transformFn(function(value) {
  if (value === null) {
    return null;
  }
  if (value === 'now') {
    value = new Date();
  }
  if (typeof value === 'string') {
    value = new Date(value);
  }
  return moment(value).toDate();
}).validateFn(function(value) {
  if (value === 'now') {
    return true;
  }
  if (value instanceof Date || (moment(new Date(value)).isValid())) {
    return true;
  }
}).encodeFn(function(value) {
  if (value === null) {
    return null;
  }
  return value.getTime();
}).decodeFn(function(value) {
  if (value === null) {
    return null;
  }
  return moment(Number(value)).toDate();
}));

AttributeDescription.registerType((new AttributeType('boolean', 'boolean')).transformFn(function(value) {
  if (typeof value === 'string') {
    value = value.toLowerCase().trim();
  }
  switch (value) {
    case true:
    case 'true':
    case 1:
    case '1':
    case 'on':
    case 'yes':
      return true;
    default:
      return false;
  }
}).validateFn(function(value) {
  if (typeof value === 'string') {
    value = value.toLowerCase().trim();
  }
  switch (value) {
    case true:
    case false:
    case 'true':
    case 'false':
    case 'on':
    case 'off':
    case '1':
    case '0':
    case 'yes':
    case 'no':
    case 1:
    case 0:
      return true;
  }
}), ['bool']);

AttributeDescription.registerType((new AttributeType('enum', 'enum')).transformFn(function(value) {
  return String(value);
}).validateFn(function(value, attribute) {
  var validValues;
  if (value === null) {
    return true;
  }
  value = String(value);
  validValues = attribute.info.values;
  if (typeof validValues === 'string') {
    validValues = validValues.split(',');
  }
  if (indexOf.call(validValues, value) < 0) {
    throw new Error('invalid value \'' + value + '\' for attribute ' + attribute.name + ' (possible values: ' + validValues.join(', ') + ')');
  }
  return true;
}));

AttributeDescription.registerType((new AttributeType('transformable', 'text')).transformFn(function(value) {
  if (typeof value === 'string') {
    value = JSON.parse(value);
  }
  return value;
}).encodeFn(function(value) {
  return JSON.stringify(value);
}));

AttributeDescription.registerType((new AttributeType('uuid', 'string')).transformFn(function(value) {
  if (value === 'uuid' || value === 'uuidv4') {
    value = uuid.v4();
  }
  return value;
}));
