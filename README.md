# squirtle

[![Package Version](https://img.shields.io/hexpm/v/squirtle)](https://hex.pm/packages/squirtle)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/squirtle/)

A JSON Patch ([RFC 6902](https://tools.ietf.org/html/rfc6902)) implementation for Gleam.

## Installation

```sh
gleam add squirtle@1
```

## Usage

### Simple String-Based API

```gleam
import gleam/io
import squirtle

pub fn main() {
  let doc = "{\"name\": \"John\", \"age\": 30}"
  let patches = "[
    {\"op\": \"replace\", \"path\": \"/name\", \"value\": \"Jane\"},
    {\"op\": \"add\", \"path\": \"/email\", \"value\": \"jane@example.com\"},
    {\"op\": \"remove\", \"path\": \"/age\"}
  ]"

  case squirtle.patch_string(doc, patches) {
    Ok(result) -> {
      io.println(result)
      // => {"name":"Jane","email":"jane@example.com"}
    }
    Error(reason) -> io.println("Patch failed: " <> reason)
  }
}
```

### Working with JsonValue

```gleam
import gleam/io
import squirtle

pub fn main() {
   let assert Ok(doc) = squirtle.json_value_parse("{\"name\": \"John\", \"age\": 30}")

   let patches = [
    squirtle.Replace(path: "/name", value: squirtle.String("Jane")),
    squirtle.Add(path: "/email", value: squirtle.String("jane@example.com")),
    squirtle.Remove(path: "/age"),
  ]

   case squirtle.patch(doc, patches) {
    Ok(result) -> {
      io.println(squirtle.json_value_to_string(result))
      // => {"name":"Jane","email":"jane@example.com"}
    }
    Error(reason) -> io.println("Patch failed: " <> reason)
  }
}
```

## Supported Operations

All operations follow the [RFC 6902](https://tools.ietf.org/html/rfc6902) specification:

| Operation | Description                                          | Example                                                        |
| --------- | ---------------------------------------------------- | -------------------------------------------------------------- |
| `add`     | Add a value at a path                                | `{"op": "add", "path": "/email", "value": "user@example.com"}` |
| `remove`  | Remove a value at a path                             | `{"op": "remove", "path": "/age"}`                             |
| `replace` | Replace a value at a path                            | `{"op": "replace", "path": "/name", "value": "Jane"}`          |
| `copy`    | Copy a value from one path to another                | `{"op": "copy", "from": "/name", "path": "/username"}`         |
| `move`    | Move a value from one path to another                | `{"op": "move", "from": "/old", "path": "/new"}`               |
| `test`    | Test that a value at a path equals an expected value | `{"op": "test", "path": "/name", "value": "John"}`             |

## JSON Pointer Paths

Paths use [JSON Pointer (RFC 6901)](https://tools.ietf.org/html/rfc6901) syntax:

| Path        | Meaning                                              |
| ----------- | ---------------------------------------------------- |
| `""`        | Root document                                        |
| `/foo`      | Property "foo" in the root object                    |
| `/foo/0`    | First element of array at "foo"                      |
| `/foo/-`    | Append to end of array at "foo" (add operation only) |
| `/foo/bar`  | Property "bar" nested in "foo"                       |
| `/foo~0bar` | Property "\~bar" (~ is escaped as ~0)                 |
| `/foo~1bar` | Property "/bar" (/ is escaped as ~1)                 |

## API Reference

Further documentation can be found at <https://hexdocs.pm/squirtle>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
