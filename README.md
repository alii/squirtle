# squirtle

[![Package Version](https://img.shields.io/hexpm/v/squirtle)](https://hex.pm/packages/squirtle)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/squirtle/)

A JSON Patch ([RFC 6902](https://tools.ietf.org/html/rfc6902)) implementation for Gleam.

## Installation

```sh
gleam add squirtle@2
```

## Usage

### Applying Patches

```gleam
import gleam/io
import squirtle.{String, Add, Replace, Remove}

pub fn main() {
  let assert Ok(doc) = squirtle.parse("{\"name\": \"John\", \"age\": 30}")

  let patches = [
    Replace(path: "/name", value: String("Jane")),
    Add(path: "/email", value: String("jane@example.com")),
    Remove(path: "/age"),
  ]

  case squirtle.apply(doc, patches) {
    Ok(result) -> io.println(squirtle.to_string(result))
    // => {"name":"Jane","email":"jane@example.com"}
    Error(err) -> io.println("Patch failed: " <> squirtle.error_to_string(err))
  }
}
```

### Generating Diffs

```gleam
import gleam/dict
import squirtle.{String, Int, Object}

pub fn main() {
  let old = Object(dict.from_list([#("name", String("John"))]))
  let new = Object(dict.from_list([
    #("name", String("Jane")),
    #("age", Int(30)),
  ]))

  let patches = squirtle.diff(from: old, to: new)
  // => [Replace("/name", String("Jane")), Add("/age", Int(30))]

  let assert Ok(result) = squirtle.apply(old, patches)
  // result == new
}
```

### Decoding from JSON

```gleam
import gleam/dynamic/decode
import gleam/json
import squirtle

pub fn apply_patch_request(doc_json: String, patches_json: String) {
  let assert Ok(doc) = json.parse(doc_json, squirtle.decoder())
  let assert Ok(patches) = json.parse(patches_json, decode.list(squirtle.patch_decoder()))

  squirtle.apply(doc, patches)
}
```

## Supported Operations

All operations follow [RFC 6902](https://tools.ietf.org/html/rfc6902):

| Operation | Description                           | Example                                                        |
| --------- | ------------------------------------- | -------------------------------------------------------------- |
| `add`     | Add a value at a path                 | `{"op": "add", "path": "/email", "value": "user@example.com"}` |
| `remove`  | Remove a value at a path              | `{"op": "remove", "path": "/age"}`                             |
| `replace` | Replace a value at a path             | `{"op": "replace", "path": "/name", "value": "Jane"}`          |
| `copy`    | Copy a value from one path to another | `{"op": "copy", "from": "/name", "path": "/username"}`         |
| `move`    | Move a value from one path to another | `{"op": "move", "from": "/old", "path": "/new"}`               |
| `test`    | Test that a value equals expected     | `{"op": "test", "path": "/name", "value": "John"}`             |

## JSON Pointer Paths

Paths use [JSON Pointer (RFC 6901)](https://tools.ietf.org/html/rfc6901) syntax:

| Path        | Meaning                             |
| ----------- | ----------------------------------- |
| `""`        | Root document                       |
| `/foo`      | Property "foo" in the root object   |
| `/foo/bar`  | Property "bar" nested in "foo"      |
| `/foo/0`    | First element of array at "foo"     |
| `/foo/-`    | Append to array at "foo" (add only) |
| `/foo~0bar` | Property "~bar" (~ escaped as ~0)   |
| `/foo~1bar` | Property "/bar" (/ escaped as ~1)   |

## API Reference

Further documentation can be found at <https://hexdocs.pm/squirtle>.

## Development

```sh
gleam test  # Run the tests
```
