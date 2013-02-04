// Generated by CoffeeScript 1.4.0
(function() {
  var $, Backbone, Drowsy, Faye, Wakeful, readVal, root, _;

  if (typeof window !== "undefined" && window !== null) {
    $ = window.$;
    _ = window._;
    Backbone = window.Backbone;
    Drowsy = window.Drowsy;
    Faye = window.Faye;
  } else {
    $ = require('jquery');
    _ = require('underscore');
    Backbone = require('backbone');
    Backbone.$ = $;
    Drowsy = require('./backbone.drowsy').Drowsy;
    Faye = require('faye');
  }

  readVal = function(context, val) {
    if (_.isFunction(val)) {
      return val.call(context);
    } else {
      return val;
    }
  };

  Wakeful = (function() {

    function Wakeful() {}

    Wakeful.subs = [];

    Wakeful.sync = function(method, obj, options) {
      var changed, deferredSync;
      deferredSync = $.Deferred();
      changed = obj.changed;
      Backbone.sync(method, obj, options).done(function() {
        var data;
        switch (method) {
          case 'create':
          case 'update':
            data = obj.toJSON();
            obj.broadcast(method, data);
            break;
          case 'patch':
            obj.broadcast(method, changed);
        }
        return deferredSync.resolve();
      });
      return deferredSync;
    };

    Wakeful.wake = function(obj, fayeUrl, options) {
      var _set;
      if (options == null) {
        options = {};
      }
      if (fayeUrl == null) {
        throw new Error("Must provide a fayeUrl");
      }
      obj.fayeUrl = fayeUrl;
      obj.broadcastEchoQueue = [];
      obj.faye = new Faye.Client(fayeUrl);
      obj.sync = Wakeful.sync;
      obj = _.extend(obj, {
        subscriptionUrl: function() {
          var coll, db, drowsyUrl, id, rx, url, _ref;
          drowsyUrl = readVal(this, this.url);
          rx = new RegExp("[a-z]+://[^/]+/?/(\\w+)/(\\w+)(?:/([0-9a-f]{24}))?");
          _ref = drowsyUrl.match(rx), url = _ref[0], db = _ref[1], coll = _ref[2], id = _ref[3];
          if (id != null) {
            return "/" + db + "/" + coll + "/" + id;
          } else {
            return "/" + db + "/" + coll + "/*";
          }
        },
        tunein: function() {
          var deferredSub;
          deferredSub = $.Deferred();
          this.sub = this.faye.subscribe(this.subscriptionUrl(), _.bind(this.receiveBroadcast, this));
          this.sub.callback(function() {
            return deferredSub.resolve();
          });
          this.sub.errback(function(err) {
            return deferredSub.reject(err);
          });
          Wakeful.subs.push(this.sub);
          return deferredSub;
        },
        tuneout: function() {
          sub.cancel();
          return delete this.sub;
        },
        broadcast: function(action, data) {
          var bcast, bid, deferredPub, pub,
            _this = this;
          deferredPub = $.Deferred();
          bid = Drowsy.generateMongoObjectId();
          bcast = {
            action: action,
            data: data,
            bid: bid
          };
          this.broadcastEchoQueue.push(deferredPub);
          pub = this.faye.publish(this.subscriptionUrl(), bcast);
          pub.callback(function() {
            _this.trigger('wakeful:broadcast:sent', bcast);
            return deferredPub.notify('sent');
          });
          pub.errback(function(err) {
            console.warn("Broadcast #" + bid + " failed!", err, bcast);
            _this.trigger('wakeful:broadcast:error', bcast, err);
            return deferredPub.reject(err);
          });
          deferredPub.pub = pub;
          deferredPub.bid = bid;
          return deferredPub;
        },
        receiveBroadcast: function(bcast) {
          var echoIndex, echoOf;
          this.trigger('wakeful:broadcast:received', bcast);
          echoOf = _.find(this.broadcastEchoQueue, function(defPub) {
            return defPub.bid === bcast.bid;
          });
          if (echoOf != null) {
            echoIndex = _.indexOf(this.broadcastEchoQueue, echoOf);
            this.broadcastEchoQueue.splice(echoIndex, 1);
            echoOf.resolve();
          }
          switch (bcast.action) {
            case 'update':
            case 'patch':
            case 'create':
              if (this.set != null) {
                return this.set(bcast.data);
              } else {
                return this.update(bcast.data, {
                  remove: false
                });
              }
              break;
            default:
              return console.warn("Don't know how to handle broadcast with action", bcast.action);
          }
        }
      });
      if (obj.add == null) {
        _set = obj.set;
        obj.set = function(key, val, options) {
          var attrs, ret;
          ret = _set.apply(this, arguments);
          if (!(options != null) && typeof val === 'object') {
            options = val;
          }
          if (options == null) {
            return ret;
          }
          if (options.broadcast) {
            if (typeof key === 'object') {
              attrs = key;
            } else {
              attrs = {};
              attrs[key] = val;
            }
            return this.broadcast('patch', attrs);
          }
        };
      }
      if (options.tunein !== false) {
        return obj.tunein();
      }
    };

    return Wakeful;

  })();

  root = typeof exports !== "undefined" && exports !== null ? exports : this;

  root.Wakeful = Wakeful;

}).call(this);
