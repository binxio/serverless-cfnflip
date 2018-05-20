'use strict';

var fs = require('fs');

module.exports.frontPage = (event, context, callback) => {
  var html = fs.readFileSync("index.html", "utf8");
  const response = {
    statusCode: 200,
    headers: {
      'Access-Control-Allow-Origin': '*', // Required for CORS support to work
      'Content-Type': 'text/html',
    },
    body: html
  };

  callback(null, response);
};
