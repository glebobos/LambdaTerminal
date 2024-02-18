# AWS Lambda Terminal

This code allows you to execute custom commands via AWS Lambda. It runs the command and logs the output to a temporary file. The logs can then be viewed in a browser-based terminal interface.


## How does it work?

The script uses the `executeCommand` function to execute a received command and write the output (& error messages) to a temporary file. The directory of the executed command is also stored; making it possible to execute context-based commands like `cd ..`.

Meanwhile, the `generateResponses` function generates a HTML template which presents an interface similar to a terminal. This allows users the ability to view the execution log of the previously executed command.

Finally, the `handler` function handles incoming event requests and extracts the IP address and command from the request. The function then executes the mentioned command and generates the HTML response which is further returned as a HTTP response.


## Usage

1. Deploy this script to AWS Lambda. Ensure it is set to run in a Amazon Linux Runtime. 
2. The `hello` handler function should be specified as your Lambda function's handler in the AWS Lambda console.

Remember to replace `YourLambdaFunctionName` with your own Lambda function name.
U can place lambda under Lambda URL invoker.


## Notes

- This script creates a unique temporary file per IP address. This means that different users (different IP addresses) will have different execution contexts (commands are executed independently).

- Ensure that your AWS Lambda function has the proper permissions to execute the commands and write to temporary files. 

- Be aware of the security implications of this script. It executes arbitrary commands received from an HTTP request. Therefore, make sure appropriate security measures are in place to ensure only trusted users can execute commands.

- Lambda Sandbox might die anytime.


## How to Secure

Here are some security recommendations in order to help protect your function:

- Use AWS IAM roles and policies to control permissions of your Lambda function.

- Limit network access by using security groups and network ACLs.

- Use AWS sign v4 mechanism via AWS_IAM lambda url.

- Monitor function invocations with AWS CloudTrail.
  
Remember, managing the security of your function is a shared responsibility between AWS and you.
