Backbone.Drowsy
===============

[Backbone.js](http://backbonejs.org/) Model + Collection classes for use with the 
[DrowsyDromedary](https://github.com/zuk/DrowsyDromedary) REST interface for [MongoDB](http://www.mongodb.org/).


Usage
-----

```js
var myDrowsyServer = new Drowsy.Server('http://localhost:9292');
var myDatabase = myDrowsyServer.database('example_db');

// extend a base Drowsy.Document (i.e. Backbone.Model) for your needs
var MyModel = myDatabase.Document('example_collection').extend({
    foobar: function() {
      return this.get('foo') * 2;
    }
  });
  
var doc = new MyModel();
doc.on('sync', function (d) {
  console.log("Doc is: "+d.toJSON());
});

doc.set('blah', 'moo');
doc.save();

doc.foobar();

// extend a base Drowsy.Collection for your needs
var MyCollection = myDatabase.Collection('example_collection').extend({
  model: MyModel
});

var coll = new MyCollection();
coll.fetch();


// you can also fetch the list of databases on a server
myDrowsyServer.databases(function (dbs) {
  (dbs[0] instanceof Drowsy.Database) === true
});

// and fetch the list of collections in a database
myDatabase.collections(function (colls) {
  (colls[0] instanceof Drowsy.Collection) == true
});
```

See the [example](https://github.com/zuk/Backbone.Drowsy/tree/master/example) 
and [test](https://github.com/zuk/Backbone.Drowsy/tree/master/test)
directories for more details.


Authentication
--------------

For basic HTTP authentication, run the following code prior to sending out 
any requests:

```js
var username = "foo";
var password = "bar";

Backbone.$.ajaxSetup({
  beforeSend: function(xhr) {
    return xhr.setRequestHeader('Authorization', 
        'Basic ' + btoa(username + ':' + password));
  }
});
```

See the AJAX configuration options for [jQuery](http://api.jquery.com/category/ajax/)
or [Zepto](http://zeptojs.com/#ajax), dependin on which Backbone sync backend you're
 using.


Browser or Node.js?
-------------------

Backbone.Drowsy should work both in a browser and under node.js.


Running Tests/Specs
-------------------

With node, `cd` into the Backbone.Drowsy directory, then install dependencies using:

`npm install`

You should now be able to run all tests in `test/`:

`cake test`




