// gm-http (v1.0) a simple HTTP server for GameMaker
// MIT License - Copyright (c) 2024 Brian LaClair
// Repository at: https://github.com/brianlaclair/gm-http
// Contributions encouraged!

/**
* Represents an HTTP server with connection handling.
* @constructor
*/
function http () constructor {

    instance    = undefined;
    connections = [];

    /**
    * Starts listening on the specified port.
    * @function listen
    * @param {real} port - The port number to listen on.
    * @returns {real} The server instance identifier.
    */
    listen = function ( port )
    {
        if (!is_undefined(instance)) { remove(); }
        self.instance = network_create_server_raw(network_socket_tcp, port, 999);
        return self.instance;
    }

    /**
    * Stops the server and clears all connections.
    * @function remove
    */  
    remove = function ()
    {
        network_destroy(self.instance);
        self.instance = undefined;

        // Clear all connections
        array_delete(self.connections, 0, array_length(self.connections));
    }

    /**
    * Intercepts a network event and processes the connection or data accordingly.
    * @function intercept
    * @returns {struct|undefined} The connection object associated with the intercepted event, or undefined if none.
    */
    intercept = function () 
    {
        
        var type                = async_load[? "type"];
        var request             = {};
        var connection_index    = undefined;

        switch (type) {
            
            case network_type_connect:
                // Create the connection
                var conn = new connection(async_load[? "socket"]);
                connection_index = array_length(self.connections);
                array_push(self.connections, conn);
                break;
            
            case network_type_data:
                // Find the correct connection and load data from the buffer
                connection_index = self.__findConnection(async_load[? "id"]); 
                var rawData = buffer_read(async_load[? "buffer"], buffer_string);

                // Parse the request
                self.connections[connection_index].parseRequest(rawData);
                break;

            case network_type_disconnect:
                connection_index = self.__findConnection(async_load[? "socket"]);
                self.connections[connection_index].disconnectTime = current_time;
                self.connections[connection_index].socket         = -1;
                break;
    
        }

        return self.connections[connection_index];

    }

    /**
    * Removes closed or inactive connections.
    * @function reap
    */
    reap = function () 
    {
        for (i = 0; i < array_length(self.connections); i++) {
            if (self.connections[i].socket == -1) {
                array_delete(self.connections, i, 1);
            }
        }
    }
    
    /**
    * Represents a single network connection.
    * @constructor
    * @param {real} sock - The socket identifier for the connection.
    */
    connection = function (sock) constructor
    {
        socket          = sock;
        connectTime     = current_time;
        disconnectTime  = undefined;
        hasRequest      = false;
        body            = false;
        request         = { body : "" };

        /**
        * Parses an incoming HTTP request string.
        * @function parseRequest
        * @param {string} requestString - The raw HTTP request string.
        */
        parseRequest = function ( requestString ) {
            var requestLines        = string_split(requestString, "\n");

            // The first line follows a different format
            if (!self.body) {
                var requestLine         = array_shift(requestLines);
                var requestLineArray    = string_split(requestLine, " ");
                self.request.method     = requestLineArray[0] ?? undefined;
                self.request.uri        = requestLineArray[1] ?? undefined;
                self.request.version    = requestLineArray[2] ?? undefined; 
            }

            // Parse the rest of the headers, and then any body that was included
            for (i = 0; i < array_length(requestLines); i++) {

            if (!self.body && string_trim(requestLines[i]) == "") {
                self.body = true;
            }

            if (!self.body) {
                var line = string_split(requestLines[i], ":");

                // TODO: header values should break down into arrays, similar to how they are set on output
                struct_set(self.request, string_lower(string_trim(line[0])), string_trim(line[1]));
            } else {
                self.request.body += requestLines[i] + "\n";
            }
            }
            
            // TODO: add logic for content-length and chunking
            self.hasRequest = true;
        }

        /**
        * Sends an HTTP response to the client.
        * @function respond
        * @param {real} [status=404] - The HTTP status code.
        * @param {string} [content=""] - The response body content.
        * @param {array<array<string>>} [headers=[]] - Custom headers to include in the response.
        */
        respond = function (status = 404, content = "", headers = []) {
            // Start the header
            var header = "HTTP/1.1 " + string(status) + " " + http.__getStatusText(status) + http.EOL;
        
            // Ensure content is resolved
            content += http.EOL;
            
            // Build header
            var headerMap = [
                ["Accept-ranges", "bytes"],
                ["Date", http.__getCurrentGmt()],
                ["Server", "GMHTTP/1.0"],
                ["Content-Type", ["text/html", "charset=utf-8"]],
                ["Content-Length", string(string_byte_length(content))],
                ["Connection", "close"]
            ]
    
            // Insert custom header attributes and overwrite where needed
            for (i = 0; i < array_length(headers); i++) {
                // Ensure that the custom header meets the criteria
                if !(array_length(headers[i]) == 2) {
                    continue;
                }
    
                // Remove any collisions from the standard header
                for (h = 0; h < array_length(headerMap); h++) {
                    if (headerMap[h][0] == headers[i][0]) {
                        array_delete(headerMap, h, 1);
                    }
                }
            }
    
            headerMap = array_concat(headerMap, headers);
    
            for (i = 0; i < array_length(headerMap); i++) {
                var attribute   = string(headerMap[i][0]);
                var value       = is_array(headerMap[i][1]) ? string_join_ext("; ", headerMap[i][1]) : string(headerMap[i][1]);
                header += attribute + ": " + value + http.EOL;
            }
    
            header += http.EOL;
    
            var result = header + content;
            
            var send_buffer = buffer_create(string_byte_length(result), buffer_fixed, 1); //Creates our buffer that we'll send
            buffer_write(send_buffer, buffer_text, result);
            var send_size = buffer_get_size(send_buffer);
            network_send_raw(self.socket, send_buffer, send_size);
            buffer_delete(send_buffer);
        }

        /**
        * Closes the connection and marks it as disconnected.
        * @function remove
        */
        remove = function () {
            network_destroy(self.socket);
            self.socket = -1;
            self.disconnectTime = current_time;
        }

        /**
        * Checks if the request has a specific header or property.
        * @function has
        * @param {string} key - The property key to check for.
        * @returns {boolean} True if the key exists, false otherwise.
        */
        has = function (key) {
            return struct_exists(self.request, key);
        }
        
        /**
        * Checks if the request has a specific header or property and returns it, or undefined
        * @function has
        * @param {string} key - The property key to retrieve
        * @returns {string|undefined} String if the key exists, undefined otherwise.
        */
        get = function (key) {
            if (self.has(key)) {
                return struct_get(self.request, key);
            }
            
            return undefined;
        }
    }

    #region Static variables, lists, and methods

    static EOL = "\r\n";

    static statusCodes = [
        { code: 100, text: "Continue" },
        { code: 101, text: "Switching Protocols" },
        { code: 102, text: "Processing" },
        { code: 103, text: "Early Hints"},
        { code: 200, text: "OK" },
        { code: 201, text: "Created" },
        { code: 202, text: "Accepted" },
        { code: 203, text: "Non-Authoritative Information" },
        { code: 204, text: "No Content" },
        { code: 205, text: "Reset Content" },
        { code: 206, text: "Partial Content" },
        { code: 207, text: "Multi-Status" },
        { code: 208, text: "Already Reported" },
        { code: 226, text: "IM Used" },
        { code: 300, text: "Multiple Choices" },
        { code: 301, text: "Moved Permanently" },
        { code: 302, text: "Found" },
        { code: 303, text: "See Other" },
        { code: 304, text: "Not Modified" },
        { code: 305, text: "Use Proxy" },
        { code: 306, text: "Switch Proxy" },
        { code: 307, text: "Temporary Redirect" },
        { code: 308, text: "Permanent Redirect" },
        { code: 400, text: "Bad Request" },
        { code: 401, text: "Unauthorized" },
        { code: 402, text: "Payment Required" },
        { code: 403, text: "Forbidden" },
        { code: 404, text: "Not Found" },
        { code: 405, text: "Method Not Allowed" },
        { code: 406, text: "Not Acceptable" },
        { code: 407, text: "Proxy Authentication Required" },
        { code: 408, text: "Request Timeout" },
        { code: 409, text: "Conflict" },
        { code: 410, text: "Gone" },
        { code: 411, text: "Length Required" },
        { code: 412, text: "Precondition Failed" },
        { code: 413, text: "Payload Too Large" },
        { code: 414, text: "URI Too Long" },
        { code: 415, text: "Unsupported Media Type" },
        { code: 416, text: "Range Not Satisfiable" },
        { code: 417, text: "Expectation Failed" },
        { code: 418, text: "I'm a Teapot" },
        { code: 421, text: "Misdirected Request" },
        { code: 422, text: "Unprocessable Entity" },
        { code: 423, text: "Locked" },
        { code: 424, text: "Failed Dependency" },
        { code: 425, text: "Too Early" },
        { code: 426, text: "Upgrade Required" },
        { code: 428, text: "Precondition Required" },
        { code: 429, text: "Too Many Requests" },
        { code: 431, text: "Request Header Fields Too Large" },
        { code: 451, text: "Unavailable For Legal Reasons" },
        { code: 500, text: "Internal Server Error" },
        { code: 501, text: "Not Implemented" },
        { code: 502, text: "Bad Gateway" },
        { code: 503, text: "Service Unavailable" },
        { code: 504, text: "Gateway Timeout" },
        { code: 505, text: "HTTP Version Not Supported" },
        { code: 506, text: "Variant Also Negotiates" },
        { code: 507, text: "Insufficient Storage" },
        { code: 508, text: "Loop Detected" },
        { code: 509, text: "Bandwidth Limit Exceeded" },
        { code: 510, text: "Not Extended" },
        { code: 511, text: "Network Authentication Required" },
    ];

    static __findConnection = function (sock) {
        for (i = 0; i < array_length(self.connections); i++) {
            if (self.connections[i].socket == sock) {
                return i;
            }
        }
        return undefined;
    }
    
    static __getCurrentGmt = function () {
        // Arrays for days and months
        var days     = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        var months   = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
            
        // Get the current time details
        var day      = days[current_weekday];
        var month    = months[current_month - 1]; // current_month is 1-based
        var date     = current_day;
        var year     = current_year;
        var hour     = string_format(current_hour, 2, 0); // Zero-padded 2-digit hour
        var minute   = string_format(current_minute, 2, 0); // Zero-padded 2-digit minute
        var second   = string_format(current_second, 2, 0); // Zero-padded 2-digit second
        
            
        // Construct the formatted string
        var datetime = day + ", " + string(date) + " " + month + " " + string(year) + " " + hour + ":" + minute + ":" + second + " GMT";
        
        return datetime;
    }

    static __getStatusText = function ( status ) { 
        for (var i = 0; i < array_length(http.statusCodes); i++) {
            if (http.statusCodes[i].code == status) {
                return http.statusCodes[i].text;
            }
        }

        return "Unknown Status";
    }

    #endregion
}


