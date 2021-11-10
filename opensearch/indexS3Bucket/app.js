
'use strict'

const AWS = require('aws-sdk');

AWS.config.region = process.env.AWS_REGION;

const s3 = new AWS.S3();

const args = require('minimist')(process.argv.slice(2));


process.env.language = 'en'

const indexCreationJson = { "mappings" : {"properties" : {"filepath" : { "type" : "text" },"filename" : { "type" : "text" },"bucket" : { "type" : "keyword" },"etag" : { "type" : "keyword" },"filesize" : { "type" : "long" }, "lastmodified" : { "type" : "date" }}}};

var numberFileObjectsUpdated = 0;
var numberFileObjectsUpdateFailed = 0;

const main = async () => {

  if (args['region'] != null) {
    process.env.AWS_REGION = args['region'];
  } else {
    throw '\'--region\' parameter is required!';
  }

  if (args['bucket'] != null) {
    process.env.bucket = args['bucket'];
  } else {
    throw '\'--bucket\' parameter is required!';
  }

  if (args['domain'] != null) {
    process.env.domain = args['domain'];
  } else {
    throw '\'--domain\' parameter is required!';
  }
  if (args['awsProfile'] != null) {
    process.env.AWS_PROFILE = args['awsProfile'];
  }
  

  console.log("\nSyncing Bucket:" + process.env.bucket + "\n\nOpenSearch Domain Endpoint:" + process.env.domain + "\n\nRegion:" + process.env.AWS_REGION);

  

  //Runtime timer begin
  console.time('indexS3Bucket');

  // Prefixes are used to fetch data in parallel.
  const numbers = '0123456789'.split('');
  const letters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
  const special = "!-_'*()".split(''); // "Safe" S3 special chars (removed . to exclude hidden directory and files)
  const prefixes = [...numbers, ...letters, ...special];

  // array of params used to call listObjectsV2 in parallel for each prefix above
  const arrayOfParams = prefixes.map((prefix) => {
    return { Bucket: process.env.bucket, Prefix: prefix }
  });

  // delete bucket index if exists
  try {
    await openSearchClient('DELETE', process.env.bucket, '');
  } catch (error) {}

  //create new bucket index
  await openSearchClient('PUT', process.env.bucket, JSON.stringify(indexCreationJson));

  await Promise.all(arrayOfParams.map(params => getAllKeys(params)));
  console.timeEnd('indexS3Bucket')
};

async function getAllKeys(params){
  var fileObjects = [];

  const response = await s3.listObjectsV2(params).promise();
  response.Contents.forEach(async function(obj) {
    fileObjects.push(
      {
        filepath: obj.Key,
        filename: obj.Key.replace(/^.*[\\\/]/, ''),
        bucket: process.env.bucket,
        etag: obj.ETag,
        filesize: obj.Size,
        lastmodified : obj.LastModified
      }
    );
  });


  var bulkUpdateResponse = indexBucketMetadata(fileObjects, process.env.bucket);

  if (bulkUpdateResponse) {
    numberFileObjectsUpdated += fileObjects.length;
  } else {
    numberFileObjectsUpdateFailed += fileObjects.length;
  }

  console.log("Total File Objects Updated:" + numberFileObjectsUpdated + " Failed:"  + numberFileObjectsUpdateFailed);
  console.timeLog("indexS3Bucket");

  if (response.NextContinuationToken) {
    params.ContinuationToken = response.NextContinuationToken;
    await getAllKeys(params); // RECURSIVE CALL
  }
}

// Load file data, save to OpenSearch Domain Instance
const indexBucketMetadata = async (payload) => {

  if (payload.length > 0) {
    var bulkRequestBody = '';
    payload.forEach(async function(obj) {
      bulkRequestBody += '{"index":{"_index":"' + process.env.bucket + '"}}\n';
      bulkRequestBody += JSON.stringify(obj) + '\n';
    });
    return await openSearchClient('PUT', '_bulk', bulkRequestBody, payload.length);
  }
}

const openSearchClient = async (httpMethod, path, requestBody, fileObjectCount) => {
  return new Promise((resolve, reject) => {
    const endpoint = new AWS.Endpoint(process.env.domain)
    let request = new AWS.HttpRequest(endpoint, process.env.AWS_REGION)

    request.method = httpMethod;
    request.path += path;
    request.body = requestBody;
    request.headers['host'] = endpoint.host;
    request.headers['Content-Type'] = 'application/json';
    request.headers['Content-Length'] = Buffer.byteLength(request.body)

    const credentials = new AWS.SharedIniFileCredentials('default')
    const signer = new AWS.Signers.V4(request, 'es')
    signer.addAuthorization(credentials, new Date())

    const client = new AWS.HttpClient()
    client.handleRequest(request, null, function(response) {
      //console.log(response.statusCode + ' ' + response.statusMessage)
      let responseBody = ''
      response.on('data', function (chunk) {
        responseBody += chunk;
      });
      response.on('end', function (chunk) {
        if (response.statusCode != 200) {
          console.log('Response body: ' + responseBody);
          reject(false);
        }
        resolve(true)
      });
    }, function(error) {
      console.log('Error: ' + error)
      reject(false)
    })
  })
}

main().catch(error => console.error(error))
