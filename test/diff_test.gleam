import gleam/dict
import gleeunit
import gleeunit/should
import squirtle

pub fn main() {
  gleeunit.main()
}

pub fn diff_simple_replace_test() {
  let from = squirtle.String("hello")
  let to = squirtle.String("world")

  let patches = squirtle.diff(from, to)

  patches
  |> should.equal([squirtle.Replace(path: "", value: squirtle.String("world"))])

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_identical_values_test() {
  let value = squirtle.Int(42)

  let patches = squirtle.diff(value, value)

  patches
  |> should.equal([])
}

pub fn diff_object_add_field_test() {
  let from =
    squirtle.Object(dict.from_list([#("name", squirtle.String("John"))]))

  let to =
    squirtle.Object(
      dict.from_list([
        #("name", squirtle.String("John")),
        #("age", squirtle.Int(30)),
      ]),
    )

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_object_remove_field_test() {
  let from =
    squirtle.Object(
      dict.from_list([
        #("name", squirtle.String("John")),
        #("age", squirtle.Int(30)),
      ]),
    )

  let to = squirtle.Object(dict.from_list([#("name", squirtle.String("John"))]))

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_object_replace_field_test() {
  let from =
    squirtle.Object(
      dict.from_list([
        #("name", squirtle.String("John")),
        #("age", squirtle.Int(30)),
      ]),
    )

  let to =
    squirtle.Object(
      dict.from_list([
        #("name", squirtle.String("Jane")),
        #("age", squirtle.Int(30)),
      ]),
    )

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_object_multiple_changes_test() {
  let from =
    squirtle.Object(
      dict.from_list([
        #("name", squirtle.String("John")),
        #("age", squirtle.Int(30)),
        #("city", squirtle.String("NYC")),
      ]),
    )

  let to =
    squirtle.Object(
      dict.from_list([
        #("name", squirtle.String("Jane")),
        #("age", squirtle.Int(30)),
        #("email", squirtle.String("jane@example.com")),
      ]),
    )

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_nested_object_test() {
  let from =
    squirtle.Object(
      dict.from_list([
        #(
          "user",
          squirtle.Object(dict.from_list([#("name", squirtle.String("John"))])),
        ),
      ]),
    )

  let to =
    squirtle.Object(
      dict.from_list([
        #(
          "user",
          squirtle.Object(dict.from_list([#("name", squirtle.String("Jane"))])),
        ),
      ]),
    )

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_array_add_elements_test() {
  let from = squirtle.Array([squirtle.Int(1), squirtle.Int(2)])
  let to =
    squirtle.Array([
      squirtle.Int(1),
      squirtle.Int(2),
      squirtle.Int(3),
      squirtle.Int(4),
    ])

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_array_remove_elements_test() {
  let from =
    squirtle.Array([
      squirtle.Int(1),
      squirtle.Int(2),
      squirtle.Int(3),
      squirtle.Int(4),
    ])
  let to = squirtle.Array([squirtle.Int(1), squirtle.Int(2)])

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_array_replace_elements_test() {
  let from = squirtle.Array([squirtle.Int(1), squirtle.Int(2), squirtle.Int(3)])
  let to =
    squirtle.Array([
      squirtle.Int(1),
      squirtle.Int(99),
      squirtle.Int(3),
    ])

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_array_mixed_changes_test() {
  let from = squirtle.Array([squirtle.Int(1), squirtle.Int(2), squirtle.Int(3)])
  let to = squirtle.Array([squirtle.Int(1), squirtle.Int(99)])

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_empty_to_nonempty_array_test() {
  let from = squirtle.Array([])
  let to = squirtle.Array([squirtle.Int(1), squirtle.Int(2)])

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_nonempty_to_empty_array_test() {
  let from = squirtle.Array([squirtle.Int(1), squirtle.Int(2)])
  let to = squirtle.Array([])

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_type_change_test() {
  let from = squirtle.String("hello")
  let to = squirtle.Int(42)

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_null_handling_test() {
  let from = squirtle.String("hello")
  let to = squirtle.Null

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_complex_nested_structure_test() {
  let from =
    squirtle.Object(
      dict.from_list([
        #("name", squirtle.String("John")),
        #(
          "addresses",
          squirtle.Array([
            squirtle.Object(
              dict.from_list([
                #("city", squirtle.String("NYC")),
                #("zip", squirtle.String("10001")),
              ]),
            ),
          ]),
        ),
        #("active", squirtle.Bool(True)),
      ]),
    )

  let to =
    squirtle.Object(
      dict.from_list([
        #("name", squirtle.String("Jane")),
        #(
          "addresses",
          squirtle.Array([
            squirtle.Object(
              dict.from_list([
                #("city", squirtle.String("LA")),
                #("zip", squirtle.String("90001")),
              ]),
            ),
            squirtle.Object(dict.from_list([#("city", squirtle.String("SF"))])),
          ]),
        ),
        #("active", squirtle.Bool(True)),
        #("premium", squirtle.Bool(True)),
      ]),
    )

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_special_characters_in_keys_test() {
  let from =
    squirtle.Object(dict.from_list([#("a/b", squirtle.String("test"))]))

  let to =
    squirtle.Object(
      dict.from_list([
        #("a/b", squirtle.String("test")),
        #("c~d", squirtle.String("value")),
      ]),
    )

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_boolean_values_test() {
  let from = squirtle.Bool(True)
  let to = squirtle.Bool(False)

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_float_values_test() {
  let from = squirtle.Float(3.14)
  let to = squirtle.Float(2.71)

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}

pub fn diff_array_of_objects_test() {
  let from =
    squirtle.Array([
      squirtle.Object(dict.from_list([#("id", squirtle.Int(1))])),
      squirtle.Object(dict.from_list([#("id", squirtle.Int(2))])),
    ])

  let to =
    squirtle.Array([
      squirtle.Object(dict.from_list([#("id", squirtle.Int(1))])),
      squirtle.Object(
        dict.from_list([
          #("id", squirtle.Int(2)),
          #("name", squirtle.String("Item 2")),
        ]),
      ),
    ])

  let patches = squirtle.diff(from, to)

  squirtle.apply(from, patches)
  |> should.equal(Ok(to))
}
