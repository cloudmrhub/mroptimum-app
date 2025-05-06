// index.js - for NotificationLambda

exports.handler = async function(event, context) {
    console.log("ConfigureBucketNotification event received:", event);
  
    return {
      Status: 'SUCCESS',
      PhysicalResourceId: context.logStreamName,
      Reason: 'Execution successful. See CloudWatch logs.',
      StackId: event.StackId,
      RequestId: event.RequestId,
      LogicalResourceId: event.LogicalResourceId,
      Data: {
        Message: 'Success'
      }
    };
  };
  