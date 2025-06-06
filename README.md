# AWS Lambda Terminal

This code allows you to execute custom commands via AWS Lambda. It runs the command and logs the output to a temporary file. The logs can then be viewed in a browser-based terminal interface.


## How does it work?

The script uses the `executeCommand` function to execute a received command and write the output (& error messages) to a temporary file. The directory of the executed command is also stored; making it possible to execute context-based commands like `cd ..`.

Meanwhile, the `generateResponses` function generates a HTML template which presents an interface similar to a terminal. This allows users the ability to view the execution log of the previously executed command.

Finally, the `handler` function handles incoming event requests and extracts the IP address and command from the request. The function then executes the mentioned command and generates the HTML response which is further returned as a HTTP response.


## Deployment with SAM

This project uses AWS Serverless Application Model (SAM) for easier deployment:

1. Make sure you have [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html) installed.

2. Use the unified script for all operations:

   ```
   # To build the project (includes JQ layer preparation)
   ./lambda-terminal.sh build
   
   # To deploy to AWS
   ./lambda-terminal.sh deploy
   
   # To do both in one command
   ./lambda-terminal.sh all
   
   # For more options
   ./lambda-terminal.sh --help
   ```

3. The deployment will create a Lambda Function URL that you can use to access your Lambda Terminal.

The JQ utility is included as a Lambda layer, so there's no need to install it separately.


## Notes

- This script creates a unique temporary file per IP address. This means that different users (different IP addresses) will have different execution contexts (commands are executed independently).

- Ensure that your AWS Lambda function has the proper permissions to execute the commands and write to temporary files. 

- Be aware of the security implications of this script. It executes arbitrary commands received from an HTTP request. Therefore, make sure appropriate security measures are in place to ensure only trusted users can execute commands.

- Lambda Sandbox might die anytime.

- The project uses a custom runtime (provided.al2) and includes the JQ utility as a Lambda layer for JSON processing.


## How to Secure

Here are some security recommendations in order to help protect your function:

- Use appropriate IAM policies to control permissions of your Lambda function.

- Limit network access by using security groups and network ACLs if decide to connect into vpc

- Use AWS sign v4 mechanism via AWS_IAM lambda url.

- Monitor function invocations with AWS CloudTrail.
  
Remember, managing the security of your function is a shared responsibility between AWS and you.

