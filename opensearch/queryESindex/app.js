/**************************
 * This program is protected under international and U.S. copyright laws as
 * an unpublished work. This program is confidential and proprietary to the
 * copyright owners. Reproduction or disclosure, in whole or in part, or the
 * production of derivative works therefrom without the express permission of
 * the copyright owners is prohibited.
 *
 * Copyright (C) 2021 GrayMeta, Inc. All rights reserved.
 * Original Author: Scott Sharp
 *
 **************************/

'use strict'

const AWS = require('aws-sdk');

const args = require('minimist')(process.argv.slice(2));


// The standard Lambda handler
const main = async () => {

  if (args['q'] == null) {
    throw '\'--q\' parameter is required!';
  }

  if (args['region'] != null) {
    process.env.AWS_REGION = args['region'];
  } else {
    throw '\'--region\' parameter is required!';
  }

  if (args['domain'] != null) {
    process.env.domain = args['domain'];
  } else {
    throw '\'--domain\' parameter is required!';
  }

  AWS.config.region = process.env.AWS_REGION;

  // Run elasticsearch query  
  try {
    const response = await queryES(args['q']);
    //const response = await queryES('filename:*app*');
    return {
      statusCode: 200,
      body: JSON.stringify(response)
    }
  } catch (err) {  
    console.error(err)
    return {
      statusCode: 500,
      body: JSON.stringify(err)
    }
  }
}

const queryES = async (q) => {
  return new Promise((resolve, reject) => {
    const endpoint = new AWS.Endpoint(process.env.domain)
    let request = new AWS.HttpRequest(endpoint, process.env.AWS_REGION)
  
    request.method = 'GET'
    request.path += '_search?q=' + q
    request.headers['host'] = process.env.domain
    request.headers['Content-Type'] = 'application/json';

    const credentials = new AWS.SharedIniFileCredentials('AWS')
    console.log(credentials)
    const signer = new AWS.Signers.V4(request, 'es')
    signer.addAuthorization(credentials, new Date())
  
    const client = new AWS.HttpClient()
    client.handleRequest(request, null, function(response) {
      console.log(response.statusCode + ' ' + response.statusMessage)
      let responseBody = ''
      response.on('data', function (chunk) {
        responseBody += chunk;
      });
      response.on('end', function (chunk) {
        console.log('Response body: ' + responseBody)
        resolve(responseBody)
      });
    }, function(error) {
      console.log('Error: ' + error)
      reject()
    })
  })
}

main().catch(error => console.error(error))
