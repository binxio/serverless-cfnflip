const exec = require('child_process').exec;

exports.handler = function(event, context, callback) {
    const child = exec('./lambdaRuby.rb ' + '\'' + JSON.stringify(event) + '\'', function(error, stdout, stderr) {
        const response = {
          statusCode: 200,
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'text/html'
          },
          body: stdout
        };
        callback(null, response);
    });
    child.stdout.on('data', console.log);
    child.stderr.on('data', console.error);
}
