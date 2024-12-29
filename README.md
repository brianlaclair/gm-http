# gm-http 🛜
#### a simple, powerful, and easy-to-implement HTTP server for [GameMaker](https://gamemaker.io/) projects

## Features
 - **Connection Management:** Automatically manage HTTP network connections. 
 - **Request Handling:** Parse HTTP requests, including headers, methods, and body content. 
 - **Response Handling:** Respond to requests with custom status codes, headers, and content.
 - **Incredibly flexible:** Serve up static pages or build dynamic experiences with GML.
 
## Getting Started

 1. Clone this repository or copy `http.gml`
 2. Drop `http.gml` into your project
 3. You're ready to go!

##  Basic Usage

### Creation
To create an HTTP server, we need to create an instance of the `http` constructor and apply a listener to it. Each HTTP instance can have one listener applied.

```gml
// Create the instance
server = new http();

// Create a listener on that instance
server.listen(8080);
```

Your `server` instance is now listening for connections on port 8080!

### Handling Requests
In an `Async - Networking` event, we can intercept requests with the aptly named `intercept` method and handle them however we'd like to.

```gml
// Intercept and handle a network event
var connection = server.intercept();

if (!is_undefined(connection) && connection.hasRequest) {
    // Check the requested URI
    if (connection.request.uri == "/example") {
        // Respond with a custom message
        connection.respond(200, "Hello, World!");
    } else {
        // Respond with 404 if not found
        connection.respond(404, "Page not found");
    }
}
```

In the code above, server.intercept() will return the relevant connection instance when it detects any event from it.

In this case, when the connection has a request, we're checking to see if it's looking for the resource at `/example` (http://localhost:8080/example, if you're following this guide) and return that resource to the client. If it's not, it will return a basic 404 page.

Pretty cool, right?

### Some house keeping...
As alluded to when talking about requests, all connections are stored as a struct (specifically as an instance of a `connection`). Your server instance keeps tabs on their connections within an array called `connections`. This means:

- When `intercept` detects a new connection, it creates a `connection`, adds it to the server-scoped `connections` array, and returns the pointer for that instance to you.
- In subsequent `Async - Networking` events, `intercept` will find the correct `connection` and return the pointer to you again.
- When a connection disconnects, or when you tell the connection you're disconnecting, the identifier contained within the `connection` will be marked as `-1`.

"But doesn't that leave me with a stale connection struct taking up memory??" I can hear you saying - and the answer is yes. There are many reasons you might still want that instance of `connection` to exist even if no one is on the other side - and who am I to judge?

When you *do* want to remove a stale `connection`, you can run the `reap` method - for most intents and purposes, you can just put it into your `Step` event like this:

```gml
server.reap();
```

Additionally, since when we call `listen` we're allocating a network port for use by GameMaker, we're going to want to make sure that it gets freed when we no longer need it. If you're utilizing a GameMaker object as the controller for your http instance, you'd likely want to explicitly free the port when that object no longer exists in that object's `Clean Up` event. Simply use the following code:
```gml
server.remove();
```

## Diving Deeper
### http() constructor
The http() constructor is the container for all things related to **gm-http**.
| Method | Arguments | Returns | Explanation |
|--|--|--|--|
| listen() | port (int) | Network Socket ID (real) | Creates a new listener on the specified port. If this method returns a number below 0, it means the creation of the server on the specified port has failed. Each instance of http() may only have one active listener at a time, so calling this again will handle removal automatically whenever necessary. |
|remove()|*[none]*|*[none]*|Destroys the currently active listener, if it exists.|
|intercept()|*[none]*|`connection`|Manages the states of all `connection` instances during events like client connecting, disconnecting, and sending data. Triggers parsing of requests (`connection.parseRequest(data)`) for each instance.|
|reap()|*[none]*|*[none]*|Removes inactive `connection` instances from the server instance.|

### connection() constructor
The connection() constructor contains all data related to a connection, stored in variables.

|Variable| Value | Explanation |
|--|--|--|
| socket | Network Socket ID (real) | The socket that this connection is on |
| connectTime | current_time at connection start (real) | The precise moment when the connection started |
| disconnectTime | current_time at connection end (real) OR undefined | The precise moment when the connection ended |
| hasRequest | boolean | If the connection has a request or not |
| body | boolean | If the request parser has switched from writing headers to writing into the body of the message |
| request | struct | Contains all request attributes and a request body if applicable |

While you can use these to directly manipulate the connection, and ultimately add more variables to store with the specific connection, there are a number of methods that assist with connection handling available on any connection() instance:

| Method | Arguments | Returns | Explanation |
|--|--|--|--|
|has()| request attribute (string)| boolean | Check if an attribute exists in the current request. Example: `connection.has("method")`|
|get()| request attribute (string)| string / undefined | Return a value from the request, if it exists. Example: `connection.get("method")` might return `GET`, `POST`, etc. or `undefined` if it has not yet been set |
| respond() | [HTTP Status Code](https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml) (int, default `404`), content (string, default empty), headers (array, default empty)|[none]|This method builds and sends a valid HTTP response to the connection with a status code, body, and overwrite-able default header segment (see below for more on custom headers)
| remove() | [none] | [none] | While a client disconnect will make the connection stale, in certain scenarios you may wish to "hang up" on a connection from the server side. |
| parseRequest() | HTTP Request (string) | [none] | Builds the connection's `request` struct from a string. In most cases, you do not need to call this method directly as [http].intercept will do it for you. | 

### Response Headers
gm-http defines a default set of response HTTP headers below your response status, specifically these ones:
```http
Accept-ranges: bytes
Date: [current formatted time]
Server: GMHTTP/1.0
Content-Type: text/html; charset=utf-8
Content-Length: [the byte length of your supplied content]
Connection: close
```
However, all of these are modifiable, and you're able to set additional headers on a per-response basis.
For example, if I wanted to specify that I'm responding with a JSON payload I could do the following:

```gml
var my_json_string = '{"Hello":"World"}';
connection.respond(200, my_json_string, [["Content-Type", "application/json"]])
```
Which supersedes the preset value of `Content-Type: text/html; charset=utf-8`.
You can also set parameters on custom headers like so:
```gml
connection.respond(200, my_json_string, [["Content-Type", ["application/json", "parameter=totally normal"]]])
```
which would output as `Content-Type: application/json; parameter=totally normal`

The custom headers array input will take an unlimited amount of array entries, so you can set any header value you like - including `Set-Cookie` entries for session management.

## Contributing
Contributions are encouraged! 
If you have ideas, questions, bug fixes, or improvements, feel free to submit a pull request or open an issue.

## License
This project is licensed under the MIT License. See the `LICENSE` file for more details.