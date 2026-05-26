import gleam/dict
import gleeunit
import gleeunit/should
import squirtle

pub fn main() {
  gleeunit.main()
}

fn sample() -> squirtle.Doc {
  squirtle.Object(
    dict.from_list([
      #(
        "users",
        squirtle.Array([
          squirtle.Object(dict.from_list([#("name", squirtle.String("John"))])),
          squirtle.Object(dict.from_list([#("name", squirtle.String("Jane"))])),
        ]),
      ),
      #("count", squirtle.Int(2)),
    ]),
  )
}

pub fn query_root_test() {
  let doc = sample()

  squirtle.query(doc, "")
  |> should.equal(Ok(doc))
}

pub fn query_object_key_test() {
  squirtle.query(sample(), "/count")
  |> should.equal(Ok(squirtle.Int(2)))
}

pub fn query_nested_array_test() {
  squirtle.query(sample(), "/users/0/name")
  |> should.equal(Ok(squirtle.String("John")))

  squirtle.query(sample(), "/users/1/name")
  |> should.equal(Ok(squirtle.String("Jane")))
}

pub fn query_missing_key_test() {
  squirtle.query(sample(), "/missing")
  |> should.equal(Error(squirtle.PathNotFound("/missing")))
}

pub fn query_index_out_of_bounds_test() {
  squirtle.query(sample(), "/users/5")
  |> should.equal(Error(squirtle.IndexOutOfBounds("/users/5", 5)))
}

pub fn query_into_scalar_test() {
  squirtle.query(sample(), "/count/nope")
  |> should.equal(Error(squirtle.NotAContainer("/count/nope")))
}
