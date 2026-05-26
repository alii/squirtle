//// JSON Patch ([RFC 6902](https://www.rfc-editor.org/rfc/rfc6902)) for Gleam.
////
//// A JSON Patch is a sequence of operations — add, remove, replace, copy,
//// move, and test — that transforms one JSON document into another. With
//// squirtle you can apply a patch to a document, compute the patch between two
//// documents (`diff`), read individual nodes (`query`), and convert documents
//// and patches to and from JSON.
////
//// Documents are the `Doc` type — a plain value you can pattern match on,
//// unlike `gleam/json`'s opaque `Json`. Operations are the `Patch` type. Paths
//// are [JSON Pointers](https://www.rfc-editor.org/rfc/rfc6901), e.g.
//// `/users/0/name`.
////
//// ```gleam
//// let assert Ok(doc) = squirtle.parse("{\"name\": \"John\"}")
//// squirtle.apply(doc, [squirtle.Replace(path: "/name", value: squirtle.String("Jane"))])
//// // => Ok(...)  // the document {"name":"Jane"}
//// ```

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

/// A JSON document.
///
/// Unlike `gleam/json`'s opaque `Json`, a `Doc` is a plain value you can
/// pattern match on and traverse directly — wrap a value in a variant to build
/// one, and match on it to take one apart. Arrays are ordered; objects are
/// keyed by string, mirroring JSON exactly. Get one with `parse`, or build it
/// by hand:
///
/// ```gleam
/// squirtle.Object(dict.from_list([
///   #("name", squirtle.String("John")),
///   #("pets", squirtle.Array([squirtle.String("Rex")])),
/// ]))
/// ```
pub type Doc {
  Null
  String(String)
  Int(Int)
  Bool(Bool)
  Float(Float)
  Array(List(Doc))
  Object(Dict(String, Doc))
}

/// A single RFC 6902 patch operation. Apply a list of these with `apply`.
///
/// Every `path` (and `from`/`to`) is a JSON Pointer: `""` is the whole
/// document, `/foo` an object key, `/foo/0` an array index, and `/foo/-` the
/// position just past the end of an array.
pub type Patch {
  /// Add `value` at `path`. For an object key this inserts or overwrites it;
  /// for an array index it inserts *before* that index (use `/-` to append).
  Add(path: String, value: Doc)

  /// Remove the value at `path`. The path must exist.
  Remove(path: String)

  /// Replace the value at `path` with `value`. The path must already exist —
  /// unlike `Add`, replace never creates a new location.
  Replace(path: String, value: Doc)

  /// Copy the value found at `from` and add it at `to`.
  Copy(from: String, to: String)

  /// Move the value at `from` to `to` (a remove followed by an add).
  Move(from: String, to: String)

  /// Succeed only if the value at `path` equals `expect`; otherwise the whole
  /// `apply` fails with `TestFailed`. Handy as a guard before other operations.
  Test(path: String, expect: Doc)
}

/// Why an `apply` or `query` failed. Render one for humans with
/// `error_to_string`.
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

/// Apply a list of patches to a document, in order.
///
/// Each patch is applied to the result of the previous one. If any patch fails
/// — a missing path, a failed `Test`, an out-of-bounds index — application
/// stops at once and returns that `Error`. Because a `Doc` is immutable, the
/// document you passed in is never left partially modified.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(doc) = squirtle.parse("{\"name\": \"John\", \"age\": 30}")
/// squirtle.apply(doc, [
///   squirtle.Replace(path: "/name", value: squirtle.String("Jane")),
///   squirtle.Remove(path: "/age"),
/// ])
/// // => Ok(...)  // the document {"name":"Jane"}
/// ```
///
/// A failing `Test` aborts the whole sequence:
///
/// ```gleam
/// squirtle.apply(doc, [
///   squirtle.Test(path: "/name", expect: squirtle.String("Bob")),
/// ])
/// // => Error(TestFailed("/name", String("Bob"), String("John")))
/// ```
pub fn apply(doc: Doc, patches: List(Patch)) -> Result(Doc, PatchError) {
  use doc, patch <- list.try_fold(patches, doc)
  case patch {
    Add(path, value) -> do_add(doc, path, value)
    Remove(path) -> do_remove(doc, path)
    Replace(path, value) -> do_replace(doc, path, value)
    Copy(from, to) -> do_copy(doc, from, to)
    Move(from, to) -> do_move(doc, from, to)
    Test(path, expect) -> do_test(doc, path, expect)
  }
}

/// Compute a patch that turns `from` into `to`.
///
/// Applying the result to `from` always reproduces `to` — that is,
/// `apply(from, diff(from, to)) == Ok(to)`. Objects are compared key by key;
/// arrays are compared by position, so an insertion near the front shows up as
/// a run of replaces plus an add rather than a minimal edit script.
///
/// ## Examples
///
/// ```gleam
/// let from = squirtle.Object(dict.from_list([#("name", squirtle.String("John"))]))
/// let to =
///   squirtle.Object(dict.from_list([
///     #("name", squirtle.String("Jane")),
///     #("age", squirtle.Int(30)),
///   ]))
///
/// squirtle.diff(from, to)
/// // => [Replace("/name", String("Jane")), Add("/age", Int(30))]
/// ```
pub fn diff(from from: Doc, to to: Doc) -> List(Patch) {
  diff_values(from, to, "")
}

/// Read the node at a JSON Pointer path.
///
/// `""` returns the whole document; otherwise each segment descends into an
/// object key or an array index. Returns an `Error` if the path is malformed
/// or points at something that isn't there. To pull the result out as a typed
/// value, pass it to `decode`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(doc) = squirtle.parse("{\"users\": [{\"name\": \"John\"}]}")
/// squirtle.query(doc, "/users/0/name")
/// // => Ok(String("John"))
/// ```
///
/// ```gleam
/// squirtle.query(doc, "/users/5")
/// // => Error(IndexOutOfBounds("/users/5", 5))
/// ```
pub fn query(doc: Doc, path: String) -> Result(Doc, PatchError) {
  use tokens <- result.try(parse_path(path))
  get_at(doc, tokens, path)
}

/// Parse a JSON string into a `Doc`.
///
/// Returns an `Error` if the input is not valid JSON.
///
/// ## Examples
///
/// ```gleam
/// squirtle.parse("{\"name\": \"John\", \"age\": 30}")
/// // => Ok(Object(...))
/// ```
///
/// ```gleam
/// squirtle.parse("{not json")
/// // => Error(...)
/// ```
pub fn parse(json_string: String) -> Result(Doc, json.DecodeError) {
  json.parse(json_string, decoder())
}

/// Parse a JSON array of operations (the on-the-wire RFC 6902 format) into a
/// list of `Patch`.
///
/// Returns an `Error` if the JSON is invalid or contains an unknown `op`.
///
/// ## Examples
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

/// Serialize a `Doc` to a compact JSON string (no extra whitespace).
///
/// ## Examples
///
/// ```gleam
/// let doc = squirtle.Object(dict.from_list([#("name", squirtle.String("John"))]))
/// squirtle.to_string(doc)
/// // => "{\"name\":\"John\"}"
/// ```
pub fn to_string(doc: Doc) -> String {
  doc |> to_json |> json.to_string
}

/// Convert a `Doc` to a `gleam/json` `Json` value.
///
/// Reach for this when you need to hand a document to code that already speaks
/// `gleam/json` — for example to nest it in a larger payload or use
/// `json.to_string_tree`. If you just want a string, `to_string` is more direct.
///
/// ## Examples
///
/// ```gleam
/// import gleam/json
/// squirtle.Int(30) |> squirtle.to_json |> json.to_string
/// // => "30"
/// ```
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

/// Serialize a single patch to its RFC 6902 JSON object string.
///
/// ## Examples
///
/// ```gleam
/// squirtle.patch_to_string(squirtle.Remove(path: "/age"))
/// // => "{\"op\":\"remove\",\"path\":\"/age\"}"
/// ```
pub fn patch_to_string(patch: Patch) -> String {
  patch |> patch_to_doc |> to_string
}

/// Serialize a list of patches to a JSON array string — the same format
/// `parse_patches` reads back.
///
/// ## Examples
///
/// ```gleam
/// squirtle.patches_to_string([
///   squirtle.Add(path: "/name", value: squirtle.String("John")),
/// ])
/// // => "[{\"op\":\"add\",\"path\":\"/name\",\"value\":\"John\"}]"
/// ```
pub fn patches_to_string(patches: List(Patch)) -> String {
  patches
  |> list.map(patch_to_doc)
  |> Array
  |> to_string
}

/// Convert a patch to the `Doc` (a JSON object) that represents it in RFC 6902
/// form. Handy if you want to serialize patches yourself instead of via
/// `patch_to_string`.
///
/// ## Examples
///
/// ```gleam
/// squirtle.patch_to_doc(squirtle.Remove(path: "/age"))
/// // => Object({"op": "remove", "path": "/age"})
/// ```
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
      Object(
        dict.from_list([#("op", String("remove")), #("path", String(path))]),
      )
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

/// A `gleam/dynamic/decode` decoder that turns any JSON value into a `Doc`.
///
/// `parse` uses this internally; reach for it directly to embed a `Doc` inside
/// a larger decoder of your own.
///
/// ## Examples
///
/// ```gleam
/// json.parse("[1, true, null]", squirtle.decoder())
/// // => Ok(Array([Int(1), Bool(True), Null]))
/// ```
pub fn decoder() -> decode.Decoder(Doc) {
  use <- decode.recursive
  decode.one_of(decode.string |> decode.map(String), [
    decode.int |> decode.map(Int),
    decode.bool |> decode.map(Bool),
    decode.float |> decode.map(Float),
    decode.list(decoder()) |> decode.map(Array),
    decode.dict(decode.string, decoder()) |> decode.map(Object),
    decode.success(Null),
  ])
}

/// A decoder for a single RFC 6902 operation object. Fails on an unrecognized
/// `op`. Combine with `decode.list` to read a whole patch — which is exactly
/// what `parse_patches` does.
///
/// ## Examples
///
/// ```gleam
/// json.parse("{\"op\":\"remove\",\"path\":\"/age\"}", squirtle.patch_decoder())
/// // => Ok(Remove("/age"))
/// ```
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

/// Convert a `Doc` to a `Dynamic` so it can be fed to a `gleam/dynamic/decode`
/// decoder. In most cases `decode` is the friendlier entry point — it wraps
/// this for you.
///
/// ## Examples
///
/// ```gleam
/// squirtle.String("hi") |> squirtle.to_dynamic |> decode.run(decode.string)
/// // => Ok("hi")
/// ```
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

/// Decode a `Doc` into one of your own types with a `gleam/dynamic/decode`
/// decoder — just as you'd decode any dynamic data.
///
/// ## Examples
///
/// ```gleam
/// let doc = squirtle.Object(dict.from_list([#("name", squirtle.String("John"))]))
/// squirtle.decode(doc, decode.at(["name"], decode.string))
/// // => Ok("John")
/// ```
pub fn decode(
  doc: Doc,
  with decoder: decode.Decoder(a),
) -> Result(a, List(decode.DecodeError)) {
  to_dynamic(doc) |> decode.run(decoder)
}

/// Render a `PatchError` as a human-readable message — for logs or for showing
/// to a user.
///
/// ## Examples
///
/// ```gleam
/// squirtle.error_to_string(squirtle.PathNotFound("/age"))
/// // => "Path not found: /age"
/// ```
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

fn list_at(items: List(a), index: Int) -> Result(a, Nil) {
  case index >= 0, list.split(items, index) {
    True, #(_, [item, ..]) -> Ok(item)
    _, _ -> Error(Nil)
  }
}

fn list_replace(items: List(a), index: Int, value: a) -> Result(List(a), Nil) {
  case index >= 0, list.split(items, index) {
    True, #(before, [_, ..after]) -> Ok(list.append(before, [value, ..after]))
    _, _ -> Error(Nil)
  }
}

fn list_remove(items: List(a), index: Int) -> Result(List(a), Nil) {
  case index >= 0, list.split(items, index) {
    True, #(before, [_, ..after]) -> Ok(list.append(before, after))
    _, _ -> Error(Nil)
  }
}

fn list_insert(items: List(a), index: Int, value: a) -> Result(List(a), Nil) {
  let #(before, after) = list.split(items, index)
  case index >= 0 && list.length(before) == index {
    True -> Ok(list.append(before, [value, ..after]))
    False -> Error(Nil)
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

fn child(doc: Doc, token: String, path: String) -> Result(Doc, PatchError) {
  case doc {
    Object(d) -> dict.get(d, token) |> result.replace_error(PathNotFound(path))
    Array(items) -> {
      use index <- result.try(parse_array_index(token, path))
      list_at(items, index)
      |> result.replace_error(IndexOutOfBounds(path, index))
    }
    _ -> Error(NotAContainer(path))
  }
}

fn get_at(
  doc: Doc,
  tokens: List(String),
  path: String,
) -> Result(Doc, PatchError) {
  list.try_fold(tokens, doc, fn(parent, token) { child(parent, token, path) })
}

/// Descend into an existing child, transform it with `then`, and rebuild the
/// container — resolving the token (and any array index) only once.
///
///     use node <- descend(doc, token, path)
fn descend(
  doc: Doc,
  token: String,
  path: String,
  then then: fn(Doc) -> Result(Doc, PatchError),
) -> Result(Doc, PatchError) {
  case doc {
    Object(d) -> {
      use node <- result.try(
        dict.get(d, token) |> result.replace_error(PathNotFound(path)),
      )
      use updated <- result.try(then(node))
      Ok(Object(dict.insert(d, token, updated)))
    }
    Array(items) -> {
      use index <- result.try(parse_array_index(token, path))
      use node <- result.try(
        list_at(items, index)
        |> result.replace_error(IndexOutOfBounds(path, index)),
      )
      use updated <- result.try(then(node))
      list_replace(items, index, updated)
      |> result.replace_error(IndexOutOfBounds(path, index))
      |> result.map(Array)
    }
    _ -> Error(NotAContainer(path))
  }
}

type SetMode {
  AddMode
  ReplaceMode
}

fn do_add(doc: Doc, path: String, value: Doc) -> Result(Doc, PatchError) {
  use tokens <- result.try(parse_path(path))
  set_at(doc, tokens, value, AddMode, path)
}

fn do_replace(doc: Doc, path: String, value: Doc) -> Result(Doc, PatchError) {
  use tokens <- result.try(parse_path(path))
  set_at(doc, tokens, value, ReplaceMode, path)
}

fn do_remove(doc: Doc, path: String) -> Result(Doc, PatchError) {
  use tokens <- result.try(parse_path(path))
  remove_at(doc, tokens, path)
}

fn do_copy(doc: Doc, from: String, to: String) -> Result(Doc, PatchError) {
  use from_tokens <- result.try(parse_path(from))
  use value <- result.try(get_at(doc, from_tokens, from))
  use to_tokens <- result.try(parse_path(to))
  set_at(doc, to_tokens, value, AddMode, to)
}

fn do_move(doc: Doc, from: String, to: String) -> Result(Doc, PatchError) {
  use from_tokens <- result.try(parse_path(from))
  use value <- result.try(get_at(doc, from_tokens, from))
  use removed <- result.try(remove_at(doc, from_tokens, from))
  use to_tokens <- result.try(parse_path(to))
  set_at(removed, to_tokens, value, AddMode, to)
}

fn do_test(doc: Doc, path: String, expect: Doc) -> Result(Doc, PatchError) {
  use tokens <- result.try(parse_path(path))
  use actual <- result.try(get_at(doc, tokens, path))
  case actual == expect {
    True -> Ok(doc)
    False -> Error(TestFailed(path, expect, actual))
  }
}

// Each walker shares `descend` for the recursive case, so the rule "every
// intermediate key must exist" lives in exactly one place. They differ only at
// the root and the final token, where each op declares its own existence rule.

fn set_at(
  doc: Doc,
  tokens: List(String),
  value: Doc,
  mode: SetMode,
  path: String,
) -> Result(Doc, PatchError) {
  case tokens {
    [] -> Ok(value)
    [token] -> set_leaf(doc, token, value, mode, path)
    [token, ..rest] -> {
      use existing <- descend(doc, token, path)
      set_at(existing, rest, value, mode, path)
    }
  }
}

fn remove_at(
  doc: Doc,
  tokens: List(String),
  path: String,
) -> Result(Doc, PatchError) {
  case tokens {
    [] -> Error(CannotRemoveRoot)
    [token] -> remove_leaf(doc, token, path)
    [token, ..rest] -> {
      use existing <- descend(doc, token, path)
      remove_at(existing, rest, path)
    }
  }
}

/// Set the final token in its container. RFC 6902 §4.3: replace requires an
/// existing target; add creates or overwrites it.
fn set_leaf(
  doc: Doc,
  token: String,
  value: Doc,
  mode: SetMode,
  path: String,
) -> Result(Doc, PatchError) {
  case doc {
    Object(d) ->
      case mode, dict.has_key(d, token) {
        ReplaceMode, False -> Error(PathNotFound(path))
        _, _ -> Ok(Object(dict.insert(d, token, value)))
      }
    Array(items) if token == "-" -> Ok(Array(list.append(items, [value])))
    Array(items) -> {
      use index <- result.try(parse_array_index(token, path))
      let inserted = case mode {
        AddMode -> list_insert(items, index, value)
        ReplaceMode -> list_replace(items, index, value)
      }
      inserted
      |> result.replace_error(IndexOutOfBounds(path, index))
      |> result.map(Array)
    }
    _ -> Error(NotAContainer(path))
  }
}

/// Remove the final token from its container; the target must exist.
fn remove_leaf(
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
    Array(items) -> {
      use index <- result.try(parse_array_index(token, path))
      list_remove(items, index)
      |> result.replace_error(IndexOutOfBounds(path, index))
      |> result.map(Array)
    }
    _ -> Error(NotAContainer(path))
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

  // Diff the common prefix element-by-element. `zip` truncates to the shorter
  // list, so this walks both lists once in lockstep (O(n)) rather than
  // indexing into them per element (which was O(n^2)).
  let change_patches =
    list.zip(from, to)
    |> list.index_map(fn(pair, idx) {
      let #(from_val, to_val) = pair
      diff_values(from_val, to_val, path <> "/" <> int.to_string(idx))
    })
    |> list.flatten

  // Anything left in `to` past the common prefix is appended.
  let add_patches =
    list.drop(to, from_len)
    |> list.map(fn(val) { Add(path: path <> "/-", value: val) })

  // Anything left in `from` past the common prefix is removed, highest index
  // first so earlier removals don't shift the indices of later ones.
  let remove_patches =
    list.drop(from, to_len)
    |> list.index_map(fn(_, i) {
      Remove(path: path <> "/" <> int.to_string(to_len + i))
    })
    |> list.reverse

  list.flatten([change_patches, add_patches, remove_patches])
}
