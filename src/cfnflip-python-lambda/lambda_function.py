# -*- coding: utf-8 -*-
import json
import sys
import cStringIO
import urlparse
from cfn_flip import flip


def print_function(word):
    return word

def lambda_handler(event, context):
    data = urlparse.parse_qsl(event["body"])
    for k, v in data:
        if k == 'code':
            plaintext = v
        else:
            plaintext = ""

    stdout_ = sys.stdout
    stream = cStringIO.StringIO()
    sys.stdout = stream
    hndlr = sys.stdout
    hndlr.write(flip(
        plaintext
    ))
    sys.stdout = stdout_
    data = stream.getvalue()

    return {
        'statusCode': 200,
        'body': json.loads(json.dumps(data)),
        'headers': {
                'Content-Type': 'plain/text',
                'Access-Control-Allow-Origin': '*',
                'Cache-control': 'private, max-age=0, no-cache'
            },
        }

