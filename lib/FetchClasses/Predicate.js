var DATE_FORMAT,
  ManagedObject,
  ManagedObjectID,
  Predicate,
  columnFunctionRegExp,
  columnNameRegExp,
  moment,
  nanRegExp,
  numberRegExp,
  operators,
  stringRegExp,
  util,
  extend = function(child, parent) {
    for (var key in parent) {
      if (hasProp.call(parent, key)) child[key] = parent[key];
    }
    function ctor() {
      this.constructor = child;
    }
    ctor.prototype = parent.prototype;
    child.prototype = new ctor();
    child.__super__ = parent.prototype;
    return child;
  },
  hasProp = {}.hasOwnProperty,
  slice = [].slice;

util = require("util");

ManagedObject = require("./../ManagedObject");

ManagedObjectID = require("./../ManagedObjectID");

moment = require("moment");

DATE_FORMAT = "YYYY-MM-DD HH:mm:ss";

numberRegExp = /\!(-?[0-9\.]+)\!/g;

nanRegExp = /\!NaN\!/g;

stringRegExp = /'[^']+'/g;

columnNameRegExp = /([a-z_][\w]+)/g;

columnFunctionRegExp = /([\w]+(\())|(\sAS\s\w+(\)))/g;

operators = {
  ">=": ">=",
  "<=": "<=",
  "!?": "NOT LIKE",
  ">": ">",
  "<": "<",
  "!": "<>",
  "?": "LIKE"
};

Predicate = (function(superClass) {
  extend(Predicate, superClass);

  function Predicate() {
    var format1, variables;
    (format1 = arguments[0]),
      (variables = 2 <= arguments.length ? slice.call(arguments, 1) : []);
    this.format = format1;
    this.variables = variables;
    this.variables = this.escapeArrayValues(this.variables);
  }

  Predicate.prototype.isObjectIDPredicate = function() {
    return this.format instanceof ManagedObjectID;
  };

  Predicate.prototype.objectID = function() {
    return this.format;
  };

  Predicate.prototype.escapeArrayValues = function(array) {
    return array.map(this.escapeValue.bind(this));
  };

  Predicate.prototype.escapeValue = function(value) {
    if (Array.isArray(value)) {
      return this.escapeArrayValues(value);
    } else if (typeof value === "string") {
      value = value.replace(/'/g, "''");
    }
    return value;
  };

  Predicate.prototype.parseObjectCondition = function(
    object,
    join,
    tableAlias
  ) {
    var _operator,
      cleanKey,
      i,
      item,
      j,
      key,
      len,
      len1,
      match,
      matches,
      operator,
      predicates,
      signature,
      string,
      value;
    if (join == null) {
      join = "AND";
    }
    if (tableAlias == null) {
      tableAlias = "SELF";
    }
    predicates = [];
    if (typeof object === "string") {
      object = new Predicate("(" + object + ")");
    }
    if (object instanceof Predicate) {
      return object.toString(this.tableAlias);
    } else if (Array.isArray(object)) {
      for (i = 0, len = object.length; i < len; i++) {
        item = object[i];
        predicates.push(this.parseObjectCondition(item));
      }
    } else {
      for (key in object) {
        value = object[key];
        operator = "=";
        for (signature in operators) {
          _operator = operators[signature];
          if (key.indexOf(signature) !== -1) {
            operator = _operator;
            key = key.replace(signature, "");
            break;
          }
        }
        if (key !== "$or" && key !== "$and") {
          cleanKey = key
            .replace(stringRegExp, "___")
            .replace(columnFunctionRegExp, "!$2$4")
            .replace(new RegExp(tableAlias + "(\\.[\\w_0-9]+)+", "gi"), "!");
          matches = cleanKey.match(columnNameRegExp);
          if (matches) {
            for (j = 0, len1 = matches.length; j < len1; j++) {
              match = matches[j];
              key = key.replace(match, tableAlias + "." + match);
            }
          }
        }
        if (value === null) {
          if (operator === "<>") {
            predicates.push(new Predicate(key + " IS NOT NULL"));
          } else {
            predicates.push(new Predicate(key + " IS NULL"));
          }
        } else if (key === "$or") {
          predicates.push(this.parseObjectCondition(value, "OR"));
        } else if (key === "$and") {
          predicates.push(this.parseObjectCondition(value, "AND"));
        } else if (Array.isArray(value) && value.length > 0) {
          predicates.push(new Predicate(key + " IN %a", value));
        } else if (typeof value === "number") {
          predicates.push(new Predicate(key + " " + operator + " %d", value));
        } else if (typeof value === "boolean") {
          predicates.push(
            new Predicate(key + " " + operator, value ? "TRUE" : "FALSE")
          );
        } else if (typeof value === "string") {
          if (operator === "LIKE" || operator === "NOT LIKE") {
            predicates.push(
              new Predicate(
                key + " " + operator + " %s",
                value.replace(/\*/g, "%").replace(/\?/g, "_")
              )
            );
          } else {
            predicates.push(new Predicate(key + " " + operator + " %s", value));
          }
        } else {
          if (value instanceof Date) {
            predicates.push(
              new Predicate(
                key + " " + operator + " %s",
                moment(value).format(DATE_FORMAT)
              )
            );
          } else if (value instanceof ManagedObject) {
            predicates.push(
              new Predicate(
                key + "_id " + operator + " %d",
                value.objectID.recordId()
              )
            );
          } else if (value instanceof ManagedObjectID) {
            predicates.push(
              new Predicate(key + "_id " + operator + " %d", value.recordId())
            );
          } else if (value && value._isAMomentObject) {
            predicates.push(
              new Predicate(
                key + " " + operator + " %s",
                value.format(DATE_FORMAT)
              )
            );
          }
        }
      }
    }
    predicates = predicates.filter(function(x) {
      return x;
    });
    if (predicates.length === 0) {
      return null;
    }
    string = predicates
      .map(function(x) {
        return x.toString();
      })
      .join(" " + join + " ");
    return "(" + string + ")";
  };

  Predicate.prototype.toString = function(tableAlias) {
    var args, format, i, len, ref, string, variable;
    if (tableAlias == null) {
      tableAlias = "SELF";
    }
    if (this.format instanceof ManagedObjectID) {
      return ManagedObjectID.idColumnName + " = " + this.format.recordId();
    } else {
      if (typeof this.format === "object") {
        return (
          this.parseObjectCondition(this.format, void 0, tableAlias) || "TRUE"
        );
      }
      format = this.format
        .replace(/[\s]*(!?=)[\s]*%@/g, "_id $1 %d")
        .replace(/%s/g, "'%s'")
        .replace(/%a/g, "%s")
        .replace(/%d/g, "!%d!");
      args = [format];
      ref = this.variables;
      for (i = 0, len = ref.length; i < len; i++) {
        variable = ref[i];
        if (variable === void 0 || variable === null) {
          variable = null;
        } else if (util.isArray(variable)) {
          variable =
            "(" +
            variable
              .map(function(x) {
                if (typeof x === "string") {
                  return "'" + x.replace(/'/g, "'") + "'";
                }
                return x;
              })
              .join(",") +
            ")";
        } else if (variable instanceof Date) {
          variable = moment(variable).format(DATE_FORMAT);
        } else if (variable instanceof ManagedObject) {
          variable = variable.objectID.recordId();
        } else if (variable instanceof ManagedObjectID) {
          variable = variable.recordId();
        } else if (variable && variable._isAMomentObject) {
          variable = variable.format(DATE_FORMAT);
        }
        args.push(variable);
      }
      string = util.format.apply(util.format, args);
      string = string.replace(numberRegExp, "$1");
      string = string.replace(nanRegExp, "'[NaN]'");
      return string;
    }
  };

  return Predicate;
})(Object);

module.exports = Predicate;
