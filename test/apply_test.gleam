import gleam/dict
import gleeunit/should
import squirtle.{Add, Int, Object, Replace, String}

// RFC 6902 §4.3: "The target location MUST exist for the operation to be
// successful." Replacing a key whose parent exists but which is itself absent
// must fail — it must NOT silently behave like `add`.
pub fn replace_missing_top_level_key_fails_test() {
  let doc = Object(dict.from_list([#("name", String("John"))]))

  squirtle.apply(doc, [Replace(path: "/age", value: Int(30))])
  |> should.be_error
}

pub fn replace_missing_nested_key_fails_test() {
  let doc = Object(dict.from_list([#("user", Object(dict.from_list([])))]))

  squirtle.apply(doc, [Replace(path: "/user/name", value: String("Jane"))])
  |> should.be_error
}

// Guard against over-correcting: replacing an existing key must still succeed.
pub fn replace_existing_key_succeeds_test() {
  let doc = Object(dict.from_list([#("name", String("John"))]))

  squirtle.apply(doc, [Replace(path: "/name", value: String("Jane"))])
  |> should.be_ok
}

// Contrast: `add` of the same missing key is allowed and creates it.
pub fn add_missing_key_succeeds_test() {
  let doc = Object(dict.from_list([#("name", String("John"))]))

  squirtle.apply(doc, [Add(path: "/age", value: Int(30))])
  |> should.be_ok
}
