var mongodb = require('mongodb'); //npm install mongodb

var uri = 'mongodb://localhost:27017/control_db'; //replace with url
//set db here
var dbs = '00_gm'  
//set schedule
var updated = ["weekly", "none", "none", "none", "none", "none", "none"] //0 Sunday

var setModifier = { $set: {} };
setModifier.$set[ "MPP.dadl."+dbs+".context.prod.maintenance.backup" ] = updated;
console.log(setModifier);

mongodb.MongoClient.connect(uri, function(error,db) {
 if (error) {
  console.log(error);
  process.exit(1);
 }

 db.collection('maintenance').update({ "document" : "dblist"},
 	 setModifier  ,
  function(error, result) {
  if (error) {
   console.log(error);
   process.exit(1);
  }
});
 process.exit(0);
});

