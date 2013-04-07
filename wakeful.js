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
    global.window = {};
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

    _.extend(Wakeful, Backbone.Events);

    if (Faye != null) {
      Wakeful.Faye = Faye;
    }

    Wakeful.subs = [];

    Wakeful.sync = function(method, obj, options) {
      var changed, data, deferredSync;
      deferredSync = $.Deferred();
      changed = obj.changed;
      data = obj.toJSON();
      Backbone.sync(method, obj, options).done(function() {
        switch (method) {
          case 'create':
          case 'update':
            if (!options.silent) {
              obj.broadcast(method, data);
            }
            break;
          case 'patch':
            if (!_.isEmpty(obj)) {
              if (!options.silent) {
                obj.broadcast(method, changed);
              }
            }
        }
        return deferredSync.resolve();
      });
      return deferredSync;
    };

    Wakeful.wake = function(obj, fayeUrl, options) {
      var _this = this;
      if (options == null) {
        options = {};
      }
      if ((obj.fayeUrl != null) && obj.fayeUrl === fayeUrl) {
        console.log(obj, "is already awake... skipping");
        return;
      }
      if (fayeUrl == null) {
        throw new Error("Must provide a fayeUrl");
      }
      obj.fayeUrl = fayeUrl;
      obj.broadcastEchoQueue = [];
      obj.faye = new Wakeful.Faye.Client(fayeUrl, {
        timeout: 15
      });
      obj.sync = Wakeful.sync;
      obj = _.extend(obj, {
        subscriptionUrl: function() {
          var coll, db, drowsyUrl, id, parsedUrl, rx, url;
          drowsyUrl = readVal(this, this.url);
          rx = /[a-z]+:\/\/[^\/]+\/([^\/\.]+)\/(\w[^\/\$]*)(?:\/([0-9a-f]{24}))?/;
          parsedUrl = drowsyUrl.match(rx);
          if (parsedUrl == null) {
            console.error(drowsyUrl, "is not a valid Drowsy URL usable with WakefulWeasel");
            throw new Error('Invalid Drowsy URL', drowsyUrl);
          }
          url = parsedUrl[0], db = parsedUrl[1], coll = parsedUrl[2], id = parsedUrl[3];
          if (id != null) {
            return "/" + db + "/" + coll + "/" + id;
          } else {
            return "/" + db + "/" + coll + "/*";
          }
        },
        tunein: function() {
          var deferredSub;
          if (this instanceof Drowsy.Document && !this.has('_id')) {
            console.error("Wakeful cannot tunein for this object because it does not yet been assigned an id!", this);
            throw new Error("Cannot call tunein() on Drowsy.Document because it has not yet been assigned an id", this);
          }
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
          var bcast, bid, deferredPub, pub, toChannel,
            _this = this;
          deferredPub = $.Deferred();
          bid = Drowsy.generateMongoObjectId();
          if (!(data._id != null) && (this.id != null)) {
            data._id = this.id;
          }
          if (data._id == null) {
            console.warn("Cannot broadcast data for a Drowsy.Document without an id!", data, this);
            deferredPub.reject('mssing_id');
            return deferredPub;
          }
          bcast = {
            action: action,
            data: data,
            bid: bid,
            origin: this.origin()
          };
          this.broadcastEchoQueue.push(deferredPub);
          toChannel = this.subscriptionUrl();
          if (this instanceof Drowsy.Collection) {
            toChannel = toChannel.replace(/\*$/, '~');
          }
          pub = this.faye.publish(toChannel, bcast);
          this.trigger('wakeful:broadcast:sent', bcast);
          deferredPub.notify('sent');
          pub.callback(function() {
            _this.trigger('wakeful:broadcast:confirmed', bcast);
            return deferredPub.notify('confirmed');
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
          var docs, echoIndex, echoOf,
            _this = this;
          echoOf = _.find(this.broadcastEchoQueue, function(defPub) {
            return defPub.bid === bcast.bid;
          });
          if (echoOf != null) {
            echoIndex = _.indexOf(this.broadcastEchoQueue, echoOf);
            this.broadcastEchoQueue.splice(echoIndex, 1);
            this.trigger('wakeful:broadcast:echo', bcast);
            echoOf.resolve();
            return;
          }
          if ((bcast.origin != null) && bcast.origin === this.origin()) {
            console.warn(this.origin(), "received broadcast from self... how did this happen?");
            return;
          }
          this.trigger('wakeful:broadcast:received', bcast);
          switch (bcast.action) {
            case 'update':
            case 'patch':
            case 'create':
              if (this instanceof Drowsy.Document) {
                return this.set(this.parse(bcast.data));
              } else {
                if (_.isArray(bcast.data)) {
                  docs = bcast.data;
                  if (bcast.action === 'patch' && !(bcast.data != null)) {
                    console.error("PATCH received by collection will be ignored because the broadcast data did not include a document id (_id)", bcast);
                    return;
                  }
                } else {
                  docs = [bcast.data];
                }
                docs = docs.map(function(doc) {
                  return _this.model.prototype.parse(doc);
                });
                return this.set(docs, {
                  remove: false
                });
              }
              break;
            default:
              return console.warn("Don't know how to handle broadcast with action", bcast.action);
          }
        },
        origin: function() {
          return readVal(this, this.url) + "#" + this.faye.getClientId();
        }
      });
      obj.faye.bind('transport:up', function() {
        _this.trigger('transport:up');
        return Wakeful.trigger('transport:up', obj);
      });
      obj.faye.bind('transport:down', function() {
        _this.trigger('transport:down');
        return Wakeful.trigger('transport:down', obj);
      });
      if (options.tunein !== false) {
        return obj.tunein();
      }
    };

    Wakeful.loadFayeClient = function(fayeUrl) {
      var deferredLoad;
      deferredLoad = $.Deferred();
      $.getScript("" + fayeUrl + "/client.js", function(script) {
        Wakeful.Faye = window.Faye;
        return deferredLoad.resolve();
      });
      return deferredLoad;
    };

    return Wakeful;

  })();

  Drowsy.Document.prototype.wake = function(fayeUrl, options) {
    if (options == null) {
      options = {};
    }
    return Wakeful.wake(this, fayeUrl, options);
  };

  Drowsy.Collection.prototype.wake = function(fayeUrl, options) {
    if (options == null) {
      options = {};
    }
    return Wakeful.wake(this, fayeUrl, options);
  };

  root = typeof exports !== "undefined" && exports !== null ? exports : this;

  root.Wakeful = Wakeful;

}).call(this);
