import gleam/dict
import gleam/json
import gleeunit/should
import squirtle

pub fn patch_to_doc_add_test() {
  let patch = squirtle.Add(path: "/name", value: squirtle.String("John"))
  let result = squirtle.patch_to_doc(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("add")),
        #("path", squirtle.String("/name")),
        #("value", squirtle.String("John")),
      ]),
    ),
  )
}

pub fn patch_to_doc_remove_test() {
  let patch = squirtle.Remove(path: "/age")
  let result = squirtle.patch_to_doc(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("remove")),
        #("path", squirtle.String("/age")),
      ]),
    ),
  )
}

pub fn patch_to_doc_replace_test() {
  let patch =
    squirtle.Replace(path: "/email", value: squirtle.String("new@example.com"))
  let result = squirtle.patch_to_doc(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("replace")),
        #("path", squirtle.String("/email")),
        #("value", squirtle.String("new@example.com")),
      ]),
    ),
  )
}

pub fn patch_to_doc_copy_test() {
  let patch = squirtle.Copy(from: "/name", to: "/nickname")
  let result = squirtle.patch_to_doc(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("copy")),
        #("from", squirtle.String("/name")),
        #("path", squirtle.String("/nickname")),
      ]),
    ),
  )
}

pub fn patch_to_doc_move_test() {
  let patch = squirtle.Move(from: "/old_name", to: "/new_name")
  let result = squirtle.patch_to_doc(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("move")),
        #("from", squirtle.String("/old_name")),
        #("path", squirtle.String("/new_name")),
      ]),
    ),
  )
}

pub fn patch_to_doc_test_test() {
  let patch = squirtle.Test(path: "/status", expect: squirtle.String("active"))
  let result = squirtle.patch_to_doc(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("test")),
        #("path", squirtle.String("/status")),
        #("value", squirtle.String("active")),
      ]),
    ),
  )
}

pub fn patch_to_string_test() {
  let patch = squirtle.Add(path: "/name", value: squirtle.String("John"))
  let result = squirtle.patch_to_string(patch)

  // Parse it back to verify it's valid JSON
  let assert Ok(parsed) = json.parse(result, squirtle.decoder())

  parsed
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("add")),
        #("path", squirtle.String("/name")),
        #("value", squirtle.String("John")),
      ]),
    ),
  )
}

pub fn round_trip_test() {
  // Create a patch, convert to string, parse back, and apply
  let patch = squirtle.Replace(path: "/name", value: squirtle.String("Jane"))
  let patch_string = squirtle.patch_to_string(patch)

  // Parse the patch back from string
  let assert Ok(parsed_patch) =
    json.parse(patch_string, squirtle.patch_decoder())

  // Verify the parsed patch is the same
  parsed_patch |> should.equal(patch)

  // Apply it to a document
  let doc =
    squirtle.Object(dict.from_list([#("name", squirtle.String("John"))]))

  let assert Ok(result) = squirtle.apply(doc, [parsed_patch])

  result
  |> should.equal(
    squirtle.Object(dict.from_list([#("name", squirtle.String("Jane"))])),
  )
}

pub fn patches_to_string_test() {
  let patches = [
    squirtle.Replace(path: "/name", value: squirtle.String("Jane")),
    squirtle.Add(path: "/age", value: squirtle.Int(30)),
    squirtle.Remove(path: "/old_field"),
  ]

  let result = squirtle.patches_to_string(patches)

  let assert Ok(parsed_patches) = squirtle.parse_patches(result)

  parsed_patches |> should.equal(patches)
}

pub fn patches_to_string_integration_test() {
  let doc1 =
    squirtle.Object(
      dict.from_list([
        #("name", squirtle.String("John")),
        #("age", squirtle.Int(25)),
      ]),
    )

  let doc2 =
    squirtle.Object(
      dict.from_list([
        #("name", squirtle.String("Jane")),
        #("age", squirtle.Int(30)),
        #("email", squirtle.String("jane@example.com")),
      ]),
    )

  let patches = squirtle.diff(doc1, doc2)

  let patches_string = squirtle.patches_to_string(patches)

  let assert Ok(received_patches) = squirtle.parse_patches(patches_string)

  let assert Ok(result) = squirtle.apply(doc1, received_patches)

  result |> should.equal(doc2)
}
