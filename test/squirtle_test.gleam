import fixture
import gleam/dynamic/decode
import gleam/option
import gleam/result
import gleeunit
import squirtle

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn hello_world_test() {
  let fixtures = fixture.load_fixtures()
  assert fixtures != []
  iter_fixtures(fixtures)
}

fn iter_fixtures(fixtures: List(fixture.Fixture)) {
  case fixtures {
    [] -> Nil
    [first, ..rest] -> {
      run_fixture(first)
      iter_fixtures(rest)
    }
  }
}

fn run_fixture(fixture: fixture.Fixture) {
  case
    squirtle.decode(
      fixture.patch,
      with: decode.list(squirtle.patch_decoder()),
    )
  {
    Ok(patches) -> {
      let r = squirtle.apply(fixture.doc, patches)

      case fixture {
        fixture.Passing(comment, _, _, expected, _) -> {
          let msg = case comment {
            option.Some(c) -> "Expected to pass: " <> c
            option.None -> "Expected to pass"
          }
          assert r == Ok(expected) as msg
        }

        fixture.Failing(comment, _, _, _, _) -> {
          let msg = case comment {
            option.Some(c) -> "Expected to fail but succeeded: " <> c
            option.None -> "Expected to fail but succeeded"
          }
          assert result.is_error(r) as msg
        }
      }
    }

    Error(_) -> {
      case fixture {
        fixture.Passing(comment, _, _, _, _) -> {
          panic as case comment {
              option.Some(c) ->
                "Failed to decode patch but expected to pass: " <> c
              option.None -> "Failed to decode patch but expected to pass"
            }
        }
        _ -> Nil
      }
    }
  }
}
