// Generated by CoffeeScript 1.4.0
(function() {
  var $, Backbone, Buffer, DROWSY_URL, Drowsy, FAYE_URL, TEST_COLLECTION, TEST_DB, Wakeful, WebSocket, btoa, should, _,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  if (typeof window !== "undefined" && window !== null) {
    $ = window.$;
    _ = window._;
    Backbone = window.Backbone;
    Drowsy = window.Drowsy;
    Wakeful = window.Wakeful;
    WebSocket = window.WebSocket;
  } else {
    $ = require('jquery');
    _ = require('underscore');
    Backbone = require('backbone');
    Backbone.$ = $;
    Drowsy = require('../backbone.drowsy').Drowsy;
    Wakeful = require('../wakeful').Wakeful;
    should = require('chai').should();
    WebSocket = require('ws');
  }

  DROWSY_URL = "http://localhost:9292";

  if (typeof FAYE_URL === "undefined" || FAYE_URL === null) {
    FAYE_URL = "http://localhost:7777/faye";
  }

  TEST_DB = 'drowsy_test';

  TEST_COLLECTION = 'tests';

  if ((typeof TEST_USERNAME !== "undefined" && TEST_USERNAME !== null) && (typeof TEST_PASSWORD !== "undefined" && TEST_PASSWORD !== null)) {
    Buffer = require('buffer').Buffer;
    btoa = function(str) {
      return (new Buffer(str || "", "ascii")).toString("base64");
    };
    Backbone.$.ajaxSetup({
      beforeSend: function(xhr) {
        return xhr.setRequestHeader('Authorization', 'Basic ' + btoa(TEST_USERNAME + ':' + TEST_PASSWORD));
      }
    });
  }

  describe('Wakeful', function() {
    this.timeout(3000);
    this.slow(1000);
    before(function() {
      var TestColl, TestDoc;
      this.server = new Drowsy.Server(DROWSY_URL);
      this.db = this.server.database(TEST_DB);
      TestDoc = (function(_super) {

        __extends(TestDoc, _super);

        function TestDoc() {
          return TestDoc.__super__.constructor.apply(this, arguments);
        }

        return TestDoc;

      })(this.db.Document(TEST_COLLECTION));
      this.TestDoc = TestDoc;
      TestColl = (function(_super) {

        __extends(TestColl, _super);

        function TestColl() {
          return TestColl.__super__.constructor.apply(this, arguments);
        }

        TestColl.prototype.model = TestDoc;

        return TestColl;

      })(this.db.Collection(TEST_COLLECTION));
      return this.TestColl = TestColl;
    });
    afterEach(function() {
      var sub, _i, _len, _ref, _results;
      _ref = Wakeful.subs;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        sub = _ref[_i];
        _results.push(sub.cancel());
      }
      return _results;
    });
    describe(".wake", function() {
      it('should enhance Drowsy.Document with wakeful functionality', function() {
        var doc;
        doc = new this.TestDoc();
        Wakeful.wake(doc, FAYE_URL);
        doc.should.have.property('tunein');
        doc.tunein.should.be.a('function');
        doc.should.have.property('broadcast');
        return doc.broadcast.should.be.a('function');
      });
      it('should automatically tunein the object', function(done) {
        var doc, dsub;
        doc = new this.TestDoc();
        dsub = Wakeful.wake(doc, FAYE_URL);
        dsub.should.have.property('resolve');
        dsub.resolve.should.be.a('function');
        return dsub.done(function() {
          return done();
        });
      });
      describe("#tunein", function() {
        it('should return a $.Deferred', function(done) {
          var doc, dsub;
          doc = new this.TestDoc();
          Wakeful.wake(doc, FAYE_URL, {
            tunein: false
          });
          dsub = doc.tunein();
          dsub.should.have.property('resolve');
          dsub.resolve.should.be.a('function');
          return dsub.done(function() {
            return done();
          });
        });
        return it('should be able to subscribe to multiple documents and collections', function(done) {
          var coll1, coll2, doc1, doc2, dsubColl1, dsubColl2, dsubDoc1, dsubDoc2;
          doc1 = new this.TestDoc();
          doc2 = new this.TestDoc();
          coll1 = new this.TestColl();
          coll2 = new this.TestColl();
          Wakeful.wake(doc1, FAYE_URL, {
            tunein: false
          });
          Wakeful.wake(doc2, FAYE_URL, {
            tunein: false
          });
          Wakeful.wake(coll1, FAYE_URL, {
            tunein: false
          });
          Wakeful.wake(coll2, FAYE_URL, {
            tunein: false
          });
          dsubDoc1 = doc1.tunein();
          dsubDoc2 = doc2.tunein();
          dsubColl1 = coll1.tunein();
          dsubColl2 = coll2.tunein();
          return $.when(dsubDoc1, dsubDoc2, dsubColl1, dsubColl2).always(function() {
            dsubDoc1.state().should.equal('resolved');
            doc1.should.have.property('sub');
            doc1.sub.should.be.an["instanceof"](Faye.Subscription);
            dsubDoc2.state().should.equal('resolved');
            doc2.should.have.property('sub');
            doc2.sub.should.be.an["instanceof"](Faye.Subscription);
            dsubColl1.state().should.equal('resolved');
            coll1.should.have.property('sub');
            coll1.sub.should.be.an["instanceof"](Faye.Subscription);
            dsubColl2.state().should.equal('resolved');
            coll2.should.have.property('sub');
            coll2.sub.should.be.an["instanceof"](Faye.Subscription);
            return done();
          });
        });
      });
      return describe("#broadcast", function() {
        it("should notify when sent, and resolve when echoed", function(done) {
          var doc;
          doc = new this.TestDoc();
          return doc.save().done(function() {
            var dsub;
            dsub = Wakeful.wake(doc, FAYE_URL);
            return dsub.done(function() {
              var dpub, rand, sent;
              rand = Math.random();
              doc.set('foo', rand);
              sent = false;
              dpub = doc.broadcast('update', doc.toJSON());
              dpub.progress(function(note) {
                note.should.equal('sent');
                return sent = true;
              });
              return dpub.always(function() {
                dpub.state().should.equal('resolved');
                return done();
              });
            });
          });
        });
        it("should send an update from one Drowsy.Document to another Drowsy.Document with the same URL", function(done) {
          var doc1, doc2;
          doc1 = new this.TestDoc();
          doc2 = new this.TestDoc();
          return doc1.save().done(function() {
            doc2.set('_id', doc1.id);
            doc2.url().should.equal(doc1.url());
            return doc2.save().done(function() {
              var dsubA, dsubB;
              dsubA = Wakeful.wake(doc1, FAYE_URL);
              dsubB = Wakeful.wake(doc2, FAYE_URL);
              dsubA.state().should.equal('pending');
              dsubB.state().should.equal('pending');
              return $.when(dsubA, dsubB).done(function() {
                var bc, rand;
                rand = Math.random();
                doc1.set('foo', rand);
                doc1.get('foo').should.equal(rand);
                doc2.has('foo').should.be["false"];
                doc2.on('change', function() {
                  doc2.get('foo').should.equal(rand);
                  return done();
                });
                bc = doc1.broadcast('update', doc1.toJSON());
                return bc.progress(function(n) {
                  return console.log(n);
                });
              });
            });
          });
        });
        return it("should send an update from a Drowsy.Document to its containing Drowsy.Collection", function(done) {
          var coll1, doc1;
          doc1 = new this.TestDoc();
          coll1 = new this.TestColl();
          return doc1.save().done(function() {
            var dsubA, dsubB;
            dsubA = Wakeful.wake(doc1, FAYE_URL);
            dsubB = Wakeful.wake(coll1, FAYE_URL);
            dsubA.state().should.equal('pending');
            dsubB.state().should.equal('pending');
            return $.when(dsubA, dsubB).done(function() {
              return coll1.fetch().done(function() {
                var bc, rand;
                rand = Math.random();
                doc1.set('foo', rand);
                doc1.get('foo').should.equal(rand);
                coll1.get(doc1.id).should.not.have.property('foo');
                coll1.on('change', function() {
                  coll1.get(doc1.id).get('foo').should.equal(rand);
                  return done();
                });
                bc = doc1.broadcast('update', doc1.toJSON());
                return bc.progress(function(n) {
                  return console.log(n);
                });
              });
            });
          });
        });
      });
    });
    describe(".set", function() {
      it("should return a deferred when the broadcast flag is set", function() {
        var doc1, dsub1;
        doc1 = new this.TestDoc();
        dsub1 = Wakeful.wake(doc1, FAYE_URL);
        return dsub1.done(function() {
          var df, rand;
          rand = Math.random();
          df = doc1.set('foo', rand, {
            broadcast: true
          });
          df.should.have.property('resolve');
          return df.resolve.should.be.a('function');
        });
      });
      it("should broadcast the change as a patch when broadcast flag is set", function(done) {
        var doc1, dsub1;
        doc1 = new this.TestDoc();
        dsub1 = Wakeful.wake(doc1, FAYE_URL);
        return dsub1.done(function() {
          var dpub, rand;
          rand = Math.random();
          dpub = doc1.set('foo', rand, {
            broadcast: true
          });
          return dpub.done(function() {
            dpub.state().should.equal('resolved');
            return done();
          });
        });
      });
      it("should should NOT persist the change when broadcast flag is set", function(done) {
        var doc1;
        doc1 = new this.TestDoc();
        doc1.set('foo', 'bar');
        return doc1.save().done(function() {
          var dsub1;
          dsub1 = Wakeful.wake(doc1, FAYE_URL);
          return dsub1.done(function() {
            var dpub, rand;
            rand = Math.random();
            dpub = doc1.set('foo', rand, {
              broadcast: true
            });
            return dpub.done(function() {
              doc1.get('foo').should.equal(rand);
              dpub.state().should.equal('resolved');
              return doc1.fetch().done(function() {
                doc1.get('foo').should.equal('bar');
                return done();
              });
            });
          });
        });
      });
      return it("should NOT broadcast the change if the broadcast flag was not set", function(done) {
        var doc1, dsub1;
        doc1 = new this.TestDoc();
        dsub1 = Wakeful.wake(doc1, FAYE_URL);
        return dsub1.done(function() {
          var dpub, rand;
          rand = Math.random();
          dpub = doc1.set('foo', rand, {
            broadcast: false
          });
          (!(dpub != null)).should.be["true"];
          return done();
        });
      });
    });
    return describe(".sync", function() {
      it("should sync an update across existing Drowsy.Documents", function(done) {
        var doc1, doc2;
        doc1 = new this.TestDoc();
        doc2 = new this.TestDoc();
        doc1.set('bar', 'a');
        return doc1.save().done(function() {
          doc2.set('_id', doc1.id);
          return doc2.fetch().done(function() {
            var dsub1, dsub2;
            doc1.toJSON().should.eql(doc2.toJSON());
            dsub1 = Wakeful.wake(doc1, FAYE_URL);
            dsub2 = Wakeful.wake(doc2, FAYE_URL);
            doc2.set('bar', 'b');
            return $.when(dsub1, dsub2).done(function() {
              var rand;
              rand = Math.random();
              doc1.set('foo', rand);
              doc2.on('change', function() {
                doc2.get('foo').should.equal(rand);
                doc2.get('bar').should.equal('a');
                return done();
              });
              return doc1.save();
            });
          });
        });
      });
      it("should sync a patch across existing Drowsy.Documents", function(done) {
        var doc1, doc2;
        doc1 = new this.TestDoc();
        doc2 = new this.TestDoc();
        doc1.set('bar', 'a');
        return doc1.save().done(function() {
          doc2.set('_id', doc1.id);
          return doc2.fetch().done(function() {
            var dsub1, dsub2;
            doc1.toJSON().should.eql(doc2.toJSON());
            dsub1 = Wakeful.wake(doc1, FAYE_URL);
            dsub2 = Wakeful.wake(doc2, FAYE_URL);
            doc2.set('bar', 'b');
            return $.when(dsub1, dsub2).done(function() {
              var rand;
              rand = Math.random();
              doc2.on('change', function() {
                doc2.get('foo').should.equal(rand);
                doc2.get('bar').should.equal('b');
                return done();
              });
              return doc1.save({
                foo: rand
              }, {
                patch: true,
                broadcast: true
              });
            });
          });
        });
      });
      return it("should sync an update from a Drowsy.Document to a Drowsy.Collection", function(done) {
        var coll1, doc1;
        doc1 = new this.TestDoc();
        coll1 = new this.TestColl();
        return doc1.save().done(function() {
          return coll1.fetch().done(function() {
            var dsub1, dsub2;
            coll1.get(doc1.id).toJSON().should.eql(doc1.toJSON());
            dsub1 = Wakeful.wake(doc1, FAYE_URL);
            dsub2 = Wakeful.wake(coll1, FAYE_URL);
            return $.when(dsub1, dsub2).done(function() {
              var rand;
              rand = Math.random();
              doc1.set('foo', rand);
              coll1.get(doc1.id).on('change', function() {
                coll1.get(doc1.id).get('foo').should.equal(rand);
                return done();
              });
              return doc1.save();
            });
          });
        });
      });
    });
  });

}).call(this);
