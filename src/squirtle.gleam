//// squirtle - RFC 6902 JSON Patch for Gleam
////
//// Apply patches to JSON documents, generate diffs, and serialize patches.

import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/dynamic/decode
import gleam/function
import gleam/int
import gleam/json
import gleam/list
import gleam/pair
import gleam/result
import gleam/set
import gleam/string

/// A JSON document that can be patched.
///
/// This is a concrete representation of JSON that supports pattern matching
/// and traversal, unlike gleam/json's opaque types.
pub type Doc {
  Null
  String(String)
  Int(Int)
  Bool(Bool)
  Float(Float)
  Array(List(Doc))
  Object(Dict(String, Doc))
}

/// An RFC 6902 JSON Patch operation.
///
/// Patches describe transformations to apply to a JSON document.
/// When applied in sequence, they transform the document step by step.
pub type Patch {
  /// Add a value at the target path. If the path points to an array index,
  /// the value is inserted at that position.
  Add(path: String, value: Doc)

  /// Remove the value at the target path.
  Remove(path: String)

  /// Replace the value at the target path with a new value.
  /// The path must already exist.
  Replace(path: String, value: Doc)

  /// Copy the value from one path to another.
  Copy(from: String, to: String)

  /// Move the value from one path to another (copy then remove).
  Move(from: String, to: String)

  /// Test that the value at a path equals the expected value.
  /// If the test fails, the entire patch operation fails.
  Test(path: String, expect: Doc)
}

/// Errors that can occur when applying patches.
pub type PatchError {
  /// The specified path does not exist in the document.
  PathNotFound(path: String)

  /// An array index in the path is invalid (not a number, has leading zeros, etc).
  InvalidIndex(path: String, index: String)

  /// An array index is outside the bounds of the array.
  IndexOutOfBounds(path: String, index: Int)

  /// Attempted to navigate into a value that is not an object or array.
  NotAContainer(path: String)

  /// Cannot remove the root document.
  CannotRemoveRoot

  /// A test operation failed because the values didn't match.
  TestFailed(path: String, expected: Doc, actual: Doc)

  /// The JSON pointer path is malformed.
  InvalidPath(reason: String)
}

/// Apply a list of patches to a document.
///
/// Patches are applied in order. If any patch fails, the operation stops
/// and returns an error. All patches must succeed for the operation to succeed.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(doc) = squirtle.parse("{\"name\": \"John\"}")
/// let patches = [
///   squirtle.Replace(path: "/name", value: squirtle.String("Jane")),
///   squirtle.Add(path: "/age", value: squirtle.Int(30)),
/// ]
/// squirtle.apply(doc, patches)
/// // => Ok(Object(...))
/// ```
pub fn apply(doc: Doc, patches: List(Patch)) -> Result(Doc, PatchError) {
  apply_loop(doc, patches)
}

/// Generate a list of patches that transform one document into another.
///
/// The returned patches, when applied to `from`, will produce `to`.
///
/// ## Example
///
/// ```gleam
/// let from = squirtle.Object(dict.from_list([
///   #("name", squirtle.String("John")),
/// ]))
/// let to = squirtle.Object(dict.from_list([
///   #("name", squirtle.String("Jane")),
///   #("age", squirtle.Int(30)),
/// ]))
///
/// squirtle.diff(from, to)
/// // => [Replace("/name", String("Jane")), Add("/age", Int(30))]
/// ```
pub fn diff(from from: Doc, to to: Doc) -> List(Patch) {
  diff_values(from, to, "")
}

/// Parse a JSON string into a Doc.
///
/// ## Example
///
/// ```gleam
/// squirtle.parse("{\"name\": \"John\", \"age\": 30}")
/// // => Ok(Object(...))
/// ```
pub fn parse(json_string: String) -> Result(Doc, json.DecodeError) {
  json.parse(json_string, decoder())
}

/// Parse a JSON array of patch operations from a string.
///
/// ## Example
///
/// ```gleam
/// squirtle.parse_patches("[{\"op\": \"add\", \"path\": \"/name\", \"value\": \"John\"}]")
/// // => Ok([Add("/name", String("John"))])
/// ```
pub fn parse_patches(
  json_string: String,
) -> Result(List(Patch), json.DecodeError) {
  json.parse(json_string, decode.list(patch_decoder()))
}

/// Convert a Doc to a JSON string.
///
/// ## Example
///
/// ```gleam
/// let doc = squirtle.Object(dict.from_list([#("name", squirtle.String("John"))]))
/// squirtle.to_string(doc)
/// // => "{\"name\":\"John\"}"
/// ```
pub fn to_string(doc: Doc) -> String {
  doc |> to_json |> json.to_string
}

/// Convert a Doc to gleam/json's Json type.
///
/// Useful when you need to integrate with code that uses the standard library.
pub fn to_json(doc: Doc) -> json.Json {
  case doc {
    String(s) -> json.string(s)
    Int(i) -> json.int(i)
    Bool(b) -> json.bool(b)
    Float(f) -> json.float(f)
    Array(arr) -> json.array(arr, to_json)
    Object(obj) -> json.dict(obj, function.identity, to_json)
    Null -> json.null()
  }
}

/// Convert a single patch to a JSON string.
pub fn patch_to_string(patch: Patch) -> String {
  patch |> patch_to_doc |> to_string
}

/// Convert a list of patches to a JSON array string.
///
/// ## Example
///
/// ```gleam
/// let patches = [
///   squirtle.Add(path: "/name", value: squirtle.String("John")),
/// ]
/// squirtle.patches_to_string(patches)
/// // => "[{\"op\":\"add\",\"path\":\"/name\",\"value\":\"John\"}]"
/// ```
pub fn patches_to_string(patches: List(Patch)) -> String {
  patches
  |> list.map(patch_to_doc)
  |> Array
  |> to_string
}

/// Convert a patch to its Doc representation (for custom serialization).
pub fn patch_to_doc(patch: Patch) -> Doc {
  case patch {
    Add(path, value) ->
      Object(
        dict.from_list([
          #("op", String("add")),
          #("path", String(path)),
          #("value", value),
        ]),
      )
    Remove(path) ->
      Object(dict.from_list([#("op", String("remove")), #("path", String(path))]))
    Replace(path, value) ->
      Object(
        dict.from_list([
          #("op", String("replace")),
          #("path", String(path)),
          #("value", value),
        ]),
      )
    Copy(from, to) ->
      Object(
        dict.from_list([
          #("op", String("copy")),
          #("from", String(from)),
          #("path", String(to)),
        ]),
      )
    Move(from, to) ->
      Object(
        dict.from_list([
          #("op", String("move")),
          #("from", String(from)),
          #("path", String(to)),
        ]),
      )
    Test(path, expect) ->
      Object(
        dict.from_list([
          #("op", String("test")),
          #("path", String(path)),
          #("value", expect),
        ]),
      )
  }
}

/// Decoder for parsing JSON into a Doc.
///
/// Use this with gleam/json.parse for custom parsing needs.
pub fn decoder() -> decode.Decoder(Doc) {
  use <- decode.recursive
  decode.one_of(str_decoder(), [
    int_decoder(),
    bool_decoder(),
    float_decoder(),
    array_decoder(),
    object_decoder(),
    null_decoder(),
  ])
}

/// Decoder for parsing a single patch operation.
pub fn patch_decoder() -> decode.Decoder(Patch) {
  use op <- decode.field("op", decode.string)

  case op {
    "add" -> {
      use path <- decode.field("path", decode.string)
      use value <- decode.field("value", decoder())
      decode.success(Add(path:, value:))
    }

    "remove" -> {
      use path <- decode.field("path", decode.string)
      decode.success(Remove(path:))
    }

    "replace" -> {
      use path <- decode.field("path", decode.string)
      use value <- decode.field("value", decoder())
      decode.success(Replace(path:, value:))
    }

    "copy" -> {
      use from <- decode.field("from", decode.string)
      use to <- decode.field("path", decode.string)
      decode.success(Copy(from:, to:))
    }

    "move" -> {
      use from <- decode.field("from", decode.string)
      use to <- decode.field("path", decode.string)
      decode.success(Move(from:, to:))
    }

    "test" -> {
      use path <- decode.field("path", decode.string)
      use expect <- decode.field("value", decoder())
      decode.success(Test(path:, expect:))
    }

    _ -> decode.failure(Copy("", ""), "Unknown op: '" <> op <> "'")
  }
}

fn str_decoder() -> decode.Decoder(Doc) {
  decode.string |> decode.map(String)
}

fn int_decoder() -> decode.Decoder(Doc) {
  decode.int |> decode.map(Int)
}

fn bool_decoder() -> decode.Decoder(Doc) {
  decode.bool |> decode.map(Bool)
}

fn float_decoder() -> decode.Decoder(Doc) {
  decode.float |> decode.map(Float)
}

fn array_decoder() -> decode.Decoder(Doc) {
  decode.list(decoder()) |> decode.map(Array)
}

fn object_decoder() -> decode.Decoder(Doc) {
  decode.dict(decode.string, decoder()) |> decode.map(Object)
}

fn null_decoder() -> decode.Decoder(Doc) {
  decode.success(Null)
}

/// Convert a Doc to a Dynamic value.
///
/// Useful when you need to decode a Doc into a custom Gleam type
/// using gleam/dynamic/decode.
pub fn to_dynamic(doc: Doc) -> dynamic.Dynamic {
  case doc {
    String(s) -> dynamic.string(s)
    Int(i) -> dynamic.int(i)
    Bool(b) -> dynamic.bool(b)
    Float(f) -> dynamic.float(f)
    Array(arr) -> dynamic.list(arr |> list.map(to_dynamic))
    Null -> dynamic.nil()
    Object(obj) -> {
      obj
      |> dict.to_list
      |> list.map(fn(p) {
        p
        |> pair.map_first(dynamic.string)
        |> pair.map_second(to_dynamic)
      })
      |> dynamic.properties
    }
  }
}

/// Decode a Doc into a custom type using a decoder.
///
/// ## Example
///
/// ```gleam
/// let doc = squirtle.Object(dict.from_list([#("name", squirtle.String("John"))]))
/// squirtle.decode(doc, decode.field("name", decode.string))
/// // => Ok("John")
/// ```
pub fn decode(
  doc: Doc,
  with decoder: decode.Decoder(a),
) -> Result(a, List(decode.DecodeError)) {
  to_dynamic(doc) |> decode.run(decoder)
}

/// Convert a PatchError to a human-readable string.
pub fn error_to_string(error: PatchError) -> String {
  case error {
    PathNotFound(path) -> "Path not found: " <> path
    InvalidIndex(path, index) ->
      "Invalid array index '" <> index <> "' at " <> path
    IndexOutOfBounds(path, index) ->
      "Array index " <> int.to_string(index) <> " out of bounds at " <> path
    NotAContainer(path) ->
      "Cannot navigate into non-object/non-array at " <> path
    CannotRemoveRoot -> "Cannot remove root document"
    TestFailed(path, _, _) -> "Test failed at " <> path
    InvalidPath(reason) -> "Invalid path: " <> reason
  }
}

fn parse_path(path: String) -> Result(List(String), PatchError) {
  case path {
    "" -> Ok([])
    "/" <> rest -> {
      string.split(rest, "/")
      |> list.map(decode_pointer_token)
      |> Ok
    }
    _ -> Error(InvalidPath("JSON Pointer must start with /"))
  }
}

fn decode_pointer_token(token: String) -> String {
  token
  |> string.replace("~1", "/")
  |> string.replace("~0", "~")
}

fn encode_pointer_token(token: String) -> String {
  token
  |> string.replace("~", "~0")
  |> string.replace("/", "~1")
}

fn get_at_index(lst: List(a), index: Int) -> Result(a, Nil) {
  case index, lst {
    _, [] -> Error(Nil)
    0, [first, ..] -> Ok(first)
    n, [_, ..rest] if n > 0 -> get_at_index(rest, n - 1)
    _, _ -> Error(Nil)
  }
}

fn parse_array_index(token: String, path: String) -> Result(Int, PatchError) {
  case token {
    "0" <> rest ->
      case rest {
        "" -> Ok(0)
        _ -> Error(InvalidIndex(path, token))
      }
    _ ->
      int.parse(token)
      |> result.replace_error(InvalidIndex(path, token))
  }
}

fn get_value(doc: Doc, path: String) -> Result(Doc, PatchError) {
  parse_path(path)
  |> result.try(navigate_get(doc, _, path))
}

fn navigate_get(
  doc: Doc,
  tokens: List(String),
  path: String,
) -> Result(Doc, PatchError) {
  case tokens {
    [] -> Ok(doc)
    [token, ..rest] ->
      case doc {
        Object(d) ->
          dict.get(d, token)
          |> result.replace_error(PathNotFound(path))
          |> result.try(navigate_get(_, rest, path))
        Array(elements) -> {
          use index <- result.try(parse_array_index(token, path))
          get_at_index(elements, index)
          |> result.replace_error(IndexOutOfBounds(path, index))
          |> result.try(navigate_get(_, rest, path))
        }
        _ -> Error(NotAContainer(path))
      }
  }
}

type SetMode {
  AddMode
  ReplaceMode
}

fn apply_loop(acc: Doc, patches: List(Patch)) -> Result(Doc, PatchError) {
  case patches {
    [] -> Ok(acc)
    [patch, ..rest] ->
      case patch {
        Add(path, value) -> do_add(acc, path, value)
        Remove(path) -> do_remove(acc, path)
        Replace(path, value) -> do_replace(acc, path, value)
        Copy(from, to) -> do_copy(acc, from, to)
        Move(from, to) -> do_move(acc, from, to)
        Test(path, expect) -> do_test(acc, path, expect)
      }
      |> result.try(apply_loop(_, rest))
  }
}

fn do_add(doc: Doc, path: String, value: Doc) -> Result(Doc, PatchError) {
  use tokens <- result.try(parse_path(path))
  navigate_set(doc, tokens, value, AddMode, path)
}

fn do_replace(doc: Doc, path: String, value: Doc) -> Result(Doc, PatchError) {
  use tokens <- result.try(parse_path(path))
  navigate_set(doc, tokens, value, ReplaceMode, path)
}

fn do_remove(doc: Doc, path: String) -> Result(Doc, PatchError) {
  use tokens <- result.try(parse_path(path))
  navigate_remove(doc, tokens, path)
}

fn do_copy(doc: Doc, from: String, to: String) -> Result(Doc, PatchError) {
  get_value(doc, from)
  |> result.try(do_add(doc, to, _))
}

fn do_move(doc: Doc, from: String, to: String) -> Result(Doc, PatchError) {
  get_value(doc, from)
  |> result.try(fn(from_value) {
    do_remove(doc, from)
    |> result.try(do_add(_, to, from_value))
  })
}

fn do_test(doc: Doc, path: String, expect: Doc) -> Result(Doc, PatchError) {
  use actual <- result.try(get_value(doc, path))
  case actual == expect {
    True -> Ok(doc)
    False -> Error(TestFailed(path, expect, actual))
  }
}

fn navigate_set(
  doc: Doc,
  tokens: List(String),
  value: Doc,
  mode: SetMode,
  original_path: String,
) -> Result(Doc, PatchError) {
  case tokens {
    [] -> Ok(value)
    [token] -> navigate_set_final(doc, token, value, mode, original_path)
    [token, ..rest] ->
      navigate_set_recursive(doc, token, rest, value, mode, original_path)
  }
}

fn navigate_set_final(
  doc: Doc,
  token: String,
  value: Doc,
  mode: SetMode,
  path: String,
) -> Result(Doc, PatchError) {
  case doc {
    Object(d) -> Ok(Object(dict.insert(d, token, value)))
    Array(elements) if token == "-" -> Ok(Array(list.append(elements, [value])))
    Array(elements) ->
      parse_array_index(token, path)
      |> result.try(fn(index) {
        insert_at_index(elements, index, value, mode)
        |> result.replace_error(IndexOutOfBounds(path, index))
      })
      |> result.map(Array)
    _ -> Error(NotAContainer(path))
  }
}

fn navigate_set_recursive(
  doc: Doc,
  token: String,
  rest: List(String),
  value: Doc,
  mode: SetMode,
  path: String,
) -> Result(Doc, PatchError) {
  case doc {
    Object(d) ->
      dict.get(d, token)
      |> result.replace_error(PathNotFound(path))
      |> result.try(navigate_set(_, rest, value, mode, path))
      |> result.map(fn(new) { Object(dict.insert(d, token, new)) })
    Array(elements) ->
      parse_array_index(token, path)
      |> result.try(fn(index) {
        get_at_index(elements, index)
        |> result.replace_error(IndexOutOfBounds(path, index))
        |> result.try(navigate_set(_, rest, value, mode, path))
        |> result.try(fn(new) {
          replace_at_index(elements, index, new)
          |> result.replace_error(IndexOutOfBounds(path, index))
        })
      })
      |> result.map(Array)
    _ -> Error(NotAContainer(path))
  }
}

fn navigate_remove(
  doc: Doc,
  tokens: List(String),
  original_path: String,
) -> Result(Doc, PatchError) {
  case tokens {
    [] -> Error(CannotRemoveRoot)
    [token] -> navigate_remove_final(doc, token, original_path)
    [token, ..rest] ->
      navigate_remove_recursive(doc, token, rest, original_path)
  }
}

fn navigate_remove_final(
  doc: Doc,
  token: String,
  path: String,
) -> Result(Doc, PatchError) {
  case doc {
    Object(d) ->
      case dict.has_key(d, token) {
        True -> Ok(Object(dict.delete(d, token)))
        False -> Error(PathNotFound(path))
      }
    Array(elements) ->
      parse_array_index(token, path)
      |> result.try(fn(index) {
        remove_at_index(elements, index)
        |> result.replace_error(IndexOutOfBounds(path, index))
      })
      |> result.map(Array)
    _ -> Error(NotAContainer(path))
  }
}

fn navigate_remove_recursive(
  doc: Doc,
  token: String,
  rest: List(String),
  path: String,
) -> Result(Doc, PatchError) {
  case doc {
    Object(d) ->
      dict.get(d, token)
      |> result.replace_error(PathNotFound(path))
      |> result.try(navigate_remove(_, rest, path))
      |> result.map(fn(new) { Object(dict.insert(d, token, new)) })
    Array(elements) ->
      parse_array_index(token, path)
      |> result.try(fn(index) {
        get_at_index(elements, index)
        |> result.replace_error(IndexOutOfBounds(path, index))
        |> result.try(navigate_remove(_, rest, path))
        |> result.try(fn(new) {
          replace_at_index(elements, index, new)
          |> result.replace_error(IndexOutOfBounds(path, index))
        })
      })
      |> result.map(Array)
    _ -> Error(NotAContainer(path))
  }
}

fn insert_at_index(
  lst: List(a),
  index: Int,
  value: a,
  mode: SetMode,
) -> Result(List(a), Nil) {
  case mode {
    AddMode -> do_insert_at_index(lst, index, value, 0)
    ReplaceMode -> replace_at_index(lst, index, value)
  }
}

fn do_insert_at_index(
  lst: List(a),
  index: Int,
  value: a,
  current: Int,
) -> Result(List(a), Nil) {
  case index == current, lst {
    True, rest -> Ok([value, ..rest])
    False, [first, ..rest] ->
      case do_insert_at_index(rest, index, value, current + 1) {
        Ok(new_rest) -> Ok([first, ..new_rest])
        Error(e) -> Error(e)
      }
    False, [] -> Error(Nil)
  }
}

fn replace_at_index(lst: List(a), index: Int, value: a) -> Result(List(a), Nil) {
  do_replace_at_index(lst, index, value, 0)
}

fn do_replace_at_index(
  lst: List(a),
  index: Int,
  value: a,
  current: Int,
) -> Result(List(a), Nil) {
  case index == current, lst {
    True, [_, ..rest] -> Ok([value, ..rest])
    False, [first, ..rest] ->
      case do_replace_at_index(rest, index, value, current + 1) {
        Ok(new_rest) -> Ok([first, ..new_rest])
        Error(e) -> Error(e)
      }
    _, [] -> Error(Nil)
  }
}

fn remove_at_index(lst: List(a), index: Int) -> Result(List(a), Nil) {
  do_remove_at_index(lst, index, 0)
}

fn do_remove_at_index(
  lst: List(a),
  index: Int,
  current: Int,
) -> Result(List(a), Nil) {
  case index == current, lst {
    True, [_, ..rest] -> Ok(rest)
    False, [first, ..rest] ->
      case do_remove_at_index(rest, index, current + 1) {
        Ok(new_rest) -> Ok([first, ..new_rest])
        Error(e) -> Error(e)
      }
    _, [] -> Error(Nil)
  }
}

fn diff_values(from: Doc, to: Doc, path: String) -> List(Patch) {
  case from == to {
    True -> []
    False ->
      case from, to {
        Object(from_obj), Object(to_obj) -> diff_objects(from_obj, to_obj, path)
        Array(from_arr), Array(to_arr) -> diff_arrays(from_arr, to_arr, path)
        _, _ -> [Replace(path: path, value: to)]
      }
  }
}

fn diff_objects(
  from: Dict(String, Doc),
  to: Dict(String, Doc),
  path: String,
) -> List(Patch) {
  let from_keys = dict.keys(from) |> set.from_list
  let to_keys = dict.keys(to) |> set.from_list

  let removed = set.difference(from_keys, to_keys)
  let remove_patches =
    set.to_list(removed)
    |> list.map(fn(key) {
      Remove(path: path <> "/" <> encode_pointer_token(key))
    })

  let added = set.difference(to_keys, from_keys)
  let add_patches =
    set.to_list(added)
    |> list.map(fn(key) {
      let assert Ok(value) = dict.get(to, key)
      Add(path: path <> "/" <> encode_pointer_token(key), value: value)
    })

  let common = set.intersection(from_keys, to_keys)
  let change_patches =
    set.to_list(common)
    |> list.flat_map(fn(key) {
      let assert Ok(from_value) = dict.get(from, key)
      let assert Ok(to_value) = dict.get(to, key)
      diff_values(
        from_value,
        to_value,
        path <> "/" <> encode_pointer_token(key),
      )
    })

  list.flatten([remove_patches, add_patches, change_patches])
}

fn diff_arrays(from: List(Doc), to: List(Doc), path: String) -> List(Patch) {
  let from_len = list.length(from)
  let to_len = list.length(to)
  let min_len = case from_len < to_len {
    True -> from_len
    False -> to_len
  }

  let change_patches = case min_len > 0 {
    True ->
      list.range(0, min_len - 1)
      |> list.flat_map(fn(idx) {
        let assert Ok(from_val) = get_at_index(from, idx)
        let assert Ok(to_val) = get_at_index(to, idx)
        diff_values(from_val, to_val, path <> "/" <> int.to_string(idx))
      })
    False -> []
  }

  let add_patches = case to_len > from_len {
    True -> {
      list.range(from_len, to_len - 1)
      |> list.map(fn(idx) {
        let assert Ok(val) = get_at_index(to, idx)
        Add(path: path <> "/-", value: val)
      })
    }
    False -> []
  }

  let remove_patches = case from_len > to_len {
    True -> {
      list.range(to_len, from_len - 1)
      |> list.reverse
      |> list.map(fn(idx) { Remove(path: path <> "/" <> int.to_string(idx)) })
    }
    False -> []
  }

  list.flatten([change_patches, add_patches, remove_patches])
}
