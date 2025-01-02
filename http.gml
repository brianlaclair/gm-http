// gm-http (v1.1.0) a simple HTTP server for GameMaker
// MIT License - Copyright (c) 2024 Brian LaClair
// Repository at: https://github.com/brianlaclair/gm-http
// Contributions encouraged!

/**
* Represents an HTTP server with connection handling.
* @constructor 
* @param {bool} [_verbose=false] - Output messages via show_debug_message
*/
function http (_verbose = false) constructor {

    instance            = undefined;
    connections         = [];
    connectionSequence  = 0;
    log                 = [];
    verbose             = _verbose;

    logger = function ( message )
    {
        if (!is_string(message)) {
            message = json_stringify(message);
        }
        var _message = $"[HTTP @ { current_time }] { message }";
        array_push(self.log, _message);
        if (self.verbose) {
            show_debug_message(_message);
        }
    }

    /**
    * Starts listening on the specified port.
    * @function listen
    * @param {real} port - The port number to listen on.
    * @returns {real|undefined} The server instance identifier.
    */
    listen = function ( port )
    {
        if (!is_undefined(instance)) { self.remove(); }
        var _listener   = network_create_server_raw(network_socket_tcp, port, 999);
        self.instance   = (_listener >= 0) ? _listener : undefined;

        var _loggerMsg  = is_undefined(self.instance) ? $"Could not start listener on port { port }" : $"Started listener on port { port }"; 
        logger(_loggerMsg);
        return self.instance;
    }

    /**
    * Stops the server and clears all connections.
    * @function remove
    */  
    remove = function ()
    {
        array_delete(self.connections, 0, array_length(self.connections));
        network_destroy(self.instance);
        self.instance = undefined;
        logger("Removed listener")
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
                logger($"({ self.connectionSequence }) Initiated connection");
                var conn = new connection(async_load[? "socket"], self.connectionSequence);
                self.connectionSequence++;
                connection_index = array_length(self.connections);
                array_push(self.connections, conn);
                break;
            
            case network_type_data:
                // Find the correct connection and load data from the buffer
                connection_index = self.__findConnection(async_load[? "id"]);
                var rawData = buffer_read(async_load[? "buffer"], buffer_string);

                // Parse the request
                self.connections[connection_index].parseRequest(rawData);

                var _id = self.connections[connection_index].connectionId; 
                logger($"({ _id }) Received data");
                
                break;

            case network_type_disconnect:
                connection_index = self.__findConnection(async_load[? "socket"]);
                self.connections[connection_index].connected      = false;
                self.connections[connection_index].disconnectTime = current_time;
                self.connections[connection_index].socket         = -1;
                
                var _id = self.connections[connection_index].connectionId; 
                logger($"({ _id }) Disconnected");

                break;
    
        }

        return self.connections[connection_index];

    }

    /**
    * Removes closed connections.
    * @function reap
    */
    reap = function () 
    {
        for (var i = 0; i < array_length(self.connections); i++) {
            if (self.connections[i].socket == -1) {
                array_delete(self.connections, i, 1);
                i--;
            }
        }
    }
    
    /**
    * Represents a single network connection.
    * @constructor
    * @param {real} sock - The socket identifier for the connection.
    */
    connection = function (sock, id = undefined) constructor
    {
        connectionId        = id;
        socket              = sock;
        connected           = true;
        connectTime         = current_time;
        disconnectTime      = undefined;
        hasRequest          = false;
        bodyStarted         = false;
        request             = { body : "", rawData: "" };

        /**
        * Parses an incoming HTTP request string.
        * @function parseRequest
        * @param {string} requestString - The raw HTTP request string.
        */
        parseRequest = function (requestString) {
          
            // Accumulate incoming data
            if (is_undefined(self.request.rawData)) {
                self.request.rawData = "";
            }

            self.request.rawData += requestString;
          
            // If we're still in the header phase, process headers
            if (!self.bodyStarted) { 
                var headerEndPos = string_pos(http.EOL + http.EOL, self.request.rawData);
          
                if (headerEndPos > 0) {
                    // Extract headers and transition to body parsing
                    var headerPart = string_copy(self.request.rawData, 1, headerEndPos);
                    var bodyPart = string_copy(self.request.rawData, headerEndPos + 4, string_length(self.request.rawData) - headerEndPos);

                    self.parseHeaders(headerPart);
                    self.bodyStarted = true;

                    // Start accumulating body data
                    self.request.body = bodyPart;
              } 
            } else { 
                // Accumulate additional body data
                self.request.body += requestString;
            }
          
          // Check if the body is complete
            if (self.bodyStarted && self.has("Content-Length")) {
                var targetLength = int64(self.get("Content-Length"));
                var currentLength = string_byte_length(self.request.body + "\n");
          
                if (currentLength >= targetLength) {
                    self.hasRequest = true;
                }
            } else if (self.bodyStarted) {
              // No Content-Length specified, consider the request complete
              self.hasRequest = true;
            }

            // Handle parsing of multipart form data
            if (self.hasRequest && self.has("Content-Type")) {
                var _originalContentType    = self.get("Content-Type");
                var _arrayContentType       = string_split(_originalContentType, ";");
                struct_set(self.request, "post", {});
                switch (string_lower(_arrayContentType[0])) {
                    case "multipart/form-data":
                        var _boundary = "--" + string_split(string_trim(_arrayContentType[1]), "=")[1]; 
                        var _bodyArr  = string_split(self.get("body"), _boundary, true);
                        array_pop(_bodyArr); // The final array entry will have just the terminating "--" string and nothing else

                        for (var i = 0; i < array_length(_bodyArr); i++) {
                            var _entry       = string_trim(_bodyArr[i]);
                            var _entryArr    = string_split(_entry, http.EOL + http.EOL);

                            var _headers     = string_trim(_entryArr[0]);
                            
                            if (array_length(_entryArr) == 1) {
                                array_push(_entryArr, "");
                            }

                            var _body        = string_trim(_entryArr[1]);

                            var _name       = ""; 
                            var _formStruct = {
                                body : _body,
                                toString : function() {
                                    return body;
                                }
                            };

                            // parse headers
                            var _headersArr  = string_split(_headers, http.EOL);
                            for (var h = 0; h < array_length(_headersArr); h++) {
                                var _headerArr = string_split(_headersArr[h], ":");
                                struct_set(_formStruct, string_lower(_headerArr[0]), string_trim(_headerArr[1]));
                            }

                            // Find content-disposition
                            var _contentDisposition     = struct_get(_formStruct, "content-disposition");
                            var _contentDispositionArr  = string_split(_contentDisposition, ";"); 
                            for (var cd = 0; cd < array_length(_contentDispositionArr); cd++) {
                                var _input = string_split(string_trim(_contentDispositionArr[cd]), "=");
                                if (_input[0] == "name") {
                                    _name = string_replace_all(_input[1], "\"", "");
                                }
                            }
                            
                            if (string_trim(_name) != "") {
                                struct_set(self.request.post, string_lower(_name), _formStruct);
                            }
                        }
                        break;

                    case "application/x-www-form-urlencoded":
                        var _bodyArr = string_split(self.get("body"), "&");
                        for (var i = 0; i < array_length(_bodyArr); i++) {
                            var _paramArr = string_split(_bodyArr[i], "=");
                            if (string_trim(_paramArr[0]) != "") {
                                struct_set(self.request.post, string_lower(_paramArr[0]), _paramArr[1]);
                            }
                        }
                        break;
                }
            }
        };

        parseHeaders = function (headerString) {
            var lines = string_split(headerString, http.EOL);

            // Process request line
            var requestLine = array_shift(lines);
            var requestLineArray = string_split(requestLine, " ");
            self.request.method = requestLineArray[0] ?? undefined;
            self.request.uri = requestLineArray[1] ?? undefined;
            self.request.version = requestLineArray[2] ?? undefined;

            // Process GET Parameters
            var _uriArr = string_split(self.request.uri, "?");
            self.request.uri = array_shift(_uriArr);
            var _getStruct = {};
            for(var i = 0; i < array_length(_uriArr); i++) {
                _getArr = string_split(_uriArr[i], "&");
                for(var g = 0; g < array_length(_getArr); g++) {
                    _getPropArr = string_split(_getArr[g], "=");
                    if (is_array(_getPropArr) && string_trim(_getPropArr[0]) != "") {
                        struct_set(_getStruct, _getPropArr[0], array_length(_getPropArr) > 1 ? _getPropArr[1] : "");
                    }
                }
            }
            
            if (struct_names_count(_getStruct)) {
                struct_set(self.request, "get", _getStruct);
            }
            
            // Process headers
            for (var i = 0; i < array_length(lines); i++) {
                var line = string_split(lines[i], ":");
                if (array_length(line) == 2) {
                    struct_set(self.request, string_lower(string_trim(line[0])), string_trim(line[1]));
                }
            }
        };


        /**
        * Sends an HTTP response to the client.
        * @function respond
        * @param {real} [status=404] - The HTTP status code.
        * @param {string} [content=""] - The response body content.
        * @param {array<array<string>>} [headers=[]] - Custom headers to include in the response.
        * @param {bool} [flush=true] - Specify if the connection's current request should be removed after responding.  
        */
        respond = function (status = 404, content = "", headers = [], flush = true) {

            // Start the header
            var header = "HTTP/1.1 " + string(status) + " " + http.__getStatusText(status) + http.EOL;
        
            // Ensure content is resolved
            content += http.EOL;
            
            // Build header
            var headerMap = [
                ["Accept-ranges", "bytes"],
                ["Date", http.__getCurrentGmt()],
                ["Server", "GM-HTTP"],
                ["Content-Type", ["text/html", "charset=utf-8"]],
                ["Content-Length", string(string_byte_length(content))],
                ["Connection", "Keep-Alive"],
                ["Keep-Alive", "timeout=15"]
            ]
    
            // Insert custom header attributes and overwrite where needed
            for (var i = 0; i < array_length(headers); i++) {
                // Ensure that the custom header meets the criteria
                if !(is_array(headers[i]) && array_length(headers[i]) == 2) {
                    array_delete(headers, i, 1);
                    i--;
                    continue;
                }
    
                // Remove any collisions from the standard header
                for (var h = 0; h < array_length(headerMap); h++) {
                    if (string_lower(headerMap[h][0]) == string_lower(headers[i][0])) {
                        array_delete(headerMap, h, 1);
                        h--;
                    }
                }
            }
    
            headerMap = array_concat(headerMap, headers);
    
            for (var i = 0; i < array_length(headerMap); i++) {
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
            
            // Automatically clear the connection's request
            if (flush) {
                self.hasRequest     = false;
                self.bodyStarted    = false;
                self.request        = { body:"", rawData:"" };
            }
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
        * @returns {bool} True if the key exists, false otherwise.
        */
        has = function (key) { 
            var _struct = struct_get(self, "request");
            
            if (string_count(".", key)) {
                var _search = string_split(key, ".", false, 1);
                if (array_length(_search) > 1) {
                    _struct = struct_get(_struct, _search[0]);
                    key     = _search[1];
                }
            }

            return struct_exists(_struct, string_lower(key));
        }
        
        /**
        * Checks if the request has a specific header or property and returns it, or undefined
        * @function has
        * @param {string} key - The property key to retrieve 
        * @returns {string} String if the key exists, undefined otherwise.
        */
        get = function (key) {
            
            if (self.has(key)) {
                var _struct = struct_get(self, "request");   

                if (string_count(".", key)) {
                    var _search = string_split(key, ".", false, 1);
                    if (array_length(_search) > 1) {
                        _struct = struct_get(_struct, _search[0]);
                        key     = _search[1];
                    }
                } 

                return string(struct_get(_struct, string_lower(key)));
            }
            
            return "";
        }
    }

    #region Static variables, lists, and methods

    static EOL = "\r\n";

    static statusCodes = [
        { code: 100, text: "Continue" }, { code: 101, text: "Switching Protocols" }, { code: 102, text: "Processing" }, { code: 103, text: "Early Hints"},
        { code: 200, text: "OK" }, { code: 201, text: "Created" }, { code: 202, text: "Accepted" }, { code: 203, text: "Non-Authoritative Information" }, { code: 204, text: "No Content" }, { code: 205, text: "Reset Content" }, { code: 206, text: "Partial Content" }, { code: 207, text: "Multi-Status" }, { code: 208, text: "Already Reported" }, { code: 226, text: "IM Used" },
        { code: 300, text: "Multiple Choices" }, { code: 301, text: "Moved Permanently" }, { code: 302, text: "Found" }, { code: 303, text: "See Other" }, { code: 304, text: "Not Modified" }, { code: 305, text: "Use Proxy" }, { code: 306, text: "Switch Proxy" }, { code: 307, text: "Temporary Redirect" }, { code: 308, text: "Permanent Redirect" },
        { code: 400, text: "Bad Request" }, { code: 401, text: "Unauthorized" }, { code: 402, text: "Payment Required" }, { code: 403, text: "Forbidden" }, { code: 404, text: "Not Found" }, { code: 405, text: "Method Not Allowed" }, { code: 406, text: "Not Acceptable" }, { code: 407, text: "Proxy Authentication Required" }, { code: 408, text: "Request Timeout" }, { code: 409, text: "Conflict" }, { code: 410, text: "Gone" }, { code: 411, text: "Length Required" }, { code: 412, text: "Precondition Failed" }, { code: 413, text: "Payload Too Large" }, { code: 414, text: "URI Too Long" }, { code: 415, text: "Unsupported Media Type" }, { code: 416, text: "Range Not Satisfiable" }, { code: 417, text: "Expectation Failed" }, { code: 418, text: "I'm a Teapot" }, { code: 421, text: "Misdirected Request" }, { code: 422, text: "Unprocessable Entity" }, { code: 423, text: "Locked" }, { code: 424, text: "Failed Dependency" }, { code: 425, text: "Too Early" }, { code: 426, text: "Upgrade Required" }, { code: 428, text: "Precondition Required" }, { code: 429, text: "Too Many Requests" }, { code: 431, text: "Request Header Fields Too Large" }, { code: 451, text: "Unavailable For Legal Reasons" },
        { code: 500, text: "Internal Server Error" }, { code: 501, text: "Not Implemented" }, { code: 502, text: "Bad Gateway" }, { code: 503, text: "Service Unavailable" }, { code: 504, text: "Gateway Timeout" }, { code: 505, text: "HTTP Version Not Supported" }, { code: 506, text: "Variant Also Negotiates" }, { code: 507, text: "Insufficient Storage" }, { code: 508, text: "Loop Detected" }, { code: 509, text: "Bandwidth Limit Exceeded" }, { code: 510, text: "Not Extended" }, { code: 511, text: "Network Authentication Required" },
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
