executeCommand() {
    local command=$1
    local identifier=$2

    [[ -f /tmp/directory_${identifier} ]] && cd $(cat /tmp/directory_${identifier}) || true

    if [ "$command" = "clear" ]; then
        >/tmp/logger_${identifier}
        return
    fi

    {
        eval "$command" || true
    } 2>>/tmp/logger_${identifier} >>/tmp/logger_${identifier}

    echo "$(pwd)" >/tmp/directory_${identifier}
}

generateResponses() {
    local identity=$1

    {
        echo "
            <html>
                <body style='background-color: #000; color: #FFF; font-family: Courier New, Courier, monospace;'>
                    <style>
                        form {
                            background-color: #000;
                            color: #FFF;
                            padding: 1px;
                            font-family: 'Courier New', Courier, monospace;
                        }
                        pre {
                            background-color: #000;
                            color: #FFF;
                            padding: 0px;
                            white-space: pre-wrap;
                            white-space: -moz-pre-wrap;
                            white-space: -pre-wrap;
                            white-space: -o-pre-wrap;
                            word-wrap: break-word;
                        }
                        input[type='text']:focus {
                            outline: none;
                        }
                    </style>
                    <pre>"

        [[ -f /tmp/logger_${identity} ]] && cat /tmp/logger_${identity}

        echo "
                    </pre>
                </body>
            </html>
        "
    } >/tmp/template.html

    {
        echo "
            <form method='GET' action=''>
                <label>$(pwd)$ </label>
                <input id='prompt' name='command' type='text' size='100' style='background-color: #000; color: #FFF; border: none;'>
                <input type='submit' style='visibility: hidden;'>
            </form>
            <script>
                window.onload = function() {
                    window.scrollTo(0,document.body.scrollHeight);
                    document.getElementById('prompt').focus();
                }
            </script> 
        "
    } >>/tmp/template.html
}

handler() {
    local event=$1
    
    # Add layer binaries to PATH
    export PATH=$PATH:/opt/bin
    
    local ipAddress=$(echo "$event" | jq -r '.headers."x-forwarded-for"')
    local parsedCommand=$(echo "$event" | jq -r '.queryStringParameters.command // ""')

    executeCommand "$parsedCommand" "$ipAddress"
    generateResponses "$ipAddress"

    local htmlResponse=$(cat /tmp/template.html)

    echo -e "{ \"isBase64Encoded\": true, \"statusCode\": 200, \"headers\": { \"Content-Type\": \"text/html\" }, \"body\": \"$(echo "$htmlResponse" | base64 | tr -d '\n')\" }"
}
