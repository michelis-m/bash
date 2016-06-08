# bash
mongod --dbpath data/db/ --auth
db.createUser({ user:"admin", pwd: "admin", roles:["root"]})
