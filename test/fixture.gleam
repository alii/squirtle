import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import simplifile
import squirtle

pub type Fixture {
  Passing(
    comment: option.Option(String),
    doc: squirtle.Doc,
    patch: squirtle.Doc,
    expected: squirtle.Doc,
    disabled: Bool,
  )
  Failing(
    comment: option.Option(String),
    doc: squirtle.Doc,
    patch: squirtle.Doc,
    error: String,
    disabled: Bool,
  )
}

pub fn fixture_decoder() {
  use disabled <- decode.optional_field("disabled", False, decode.bool)
  use doc <- decode.field("doc", squirtle.decoder())
  use comment <- decode.optional_field(
    "comment",
    option.None,
    decode.string |> decode.map(option.Some),
  )
  use patch <- decode.field("patch", squirtle.decoder())
  use expected <- decode.optional_field(
    "expected",
    option.None,
    squirtle.decoder() |> decode.map(fn(val) { option.Some(val) }),
  )

  case expected {
    option.Some(expected) ->
      decode.success(Passing(comment:, doc:, patch:, expected:, disabled:))
    option.None -> {
      use error <- decode.optional_field("error", "", decode.string)
      decode.success(Failing(comment:, doc:, patch:, error:, disabled:))
    }
  }
}

pub fn load_fixtures_from_file(file) {
  let assert Ok(json_string) = simplifile.read(file)
  let assert Ok(fixtures) =
    json.parse(json_string, decode.list(fixture_decoder()))
  fixtures
}

pub fn load_fixtures() {
  []
  |> list.append(load_fixtures_from_file("./test/spec_tests.json"))
  |> list.append(load_fixtures_from_file("./test/tests.json"))
  |> list.filter(fn(f) { !f.disabled })
}
