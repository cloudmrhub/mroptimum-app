const AWS = require("aws-sdk");

exports.handler = async function(event, context) {
  const s3 = new AWS.S3();

  const responseBody = {
    Status: "SUCCESS",
    Reason: `See CloudWatch for details: ${context.logStreamName}`,
    PhysicalResourceId: context.logStreamName,
    StackId: event.StackId,
    RequestId: event.RequestId,
    LogicalResourceId: event.LogicalResourceId,
    Data: {}
  };

  const sendResponse = async (responseStatus) => {
    const https = require("https");
    const url = require("url");
    const responseBodyStr = JSON.stringify({ ...responseBody, Status: responseStatus });
    const parsedUrl = url.parse(event.ResponseURL);
    const options = {
      hostname: parsedUrl.hostname,
      port: 443,
      path: parsedUrl.path,
      method: "PUT",
      headers: {
        "Content-Type": "",
        "Content-Length": responseBodyStr.length
      }
    };

    return new Promise((resolve, reject) => {
      const req = https.request(options, (res) => resolve());
      req.on("error", (e) => reject(e));
      req.write(responseBodyStr);
      req.end();
    });
  };

  try {
    const bucket = event.ResourceProperties.BucketName;
    const config = event.ResourceProperties.NotificationConfiguration;
    await s3.putBucketNotificationConfiguration({
      Bucket: bucket,
      NotificationConfiguration: config
    }).promise();
    await sendResponse("SUCCESS");
  } catch (e) {
    console.log(e);
    await sendResponse("FAILED");
  }
};
