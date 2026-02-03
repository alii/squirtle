import gleam/dynamic/decode
import gleam/io
import gleam/json
import squirtle.{Add, Copy, Move, Remove, Replace, String, Test}

pub fn main() {
  io.println("")

  // Example 1: Basic patch operations
  io.println("1. Basic patch operations:")
  let assert Ok(doc) = squirtle.parse("{\"name\": \"John\", \"age\": 30}")

  let patches = [
    Replace(path: "/name", value: String("Jane")),
    Add(path: "/email", value: String("jane@example.com")),
    Remove(path: "/age"),
  ]

  case squirtle.apply(doc, patches) {
    Ok(result) -> {
      io.println("  Input:  {\"name\": \"John\", \"age\": 30}")
      io.println("  Output: " <> squirtle.to_string(result))
    }
    Error(err) -> io.println("  Error: " <> squirtle.error_to_string(err))
  }

  io.println("")

  // Example 2: Working with arrays
  io.println("2. Array operations:")
  let assert Ok(doc) = squirtle.parse("{\"users\": [\"Alice\", \"Bob\"]}")

  let patches = [
    Add(path: "/users/-", value: String("Charlie")),
    Add(path: "/users/1", value: String("Dave")),
  ]

  case squirtle.apply(doc, patches) {
    Ok(result) -> {
      io.println("  Input:  {\"users\": [\"Alice\", \"Bob\"]}")
      io.println("  Output: " <> squirtle.to_string(result))
    }
    Error(err) -> io.println("  Error: " <> squirtle.error_to_string(err))
  }

  io.println("")

  // Example 3: Copy and move operations
  io.println("3. Copy and move:")
  let assert Ok(doc) =
    squirtle.parse("{\"name\": \"John\", \"address\": {\"city\": \"NYC\"}}")

  let patches = [
    Copy(from: "/name", to: "/username"),
    Move(from: "/address/city", to: "/city"),
  ]

  case squirtle.apply(doc, patches) {
    Ok(result) -> {
      io.println("  Input:  {\"name\": \"John\", \"address\": {\"city\": \"NYC\"}}")
      io.println("  Output: " <> squirtle.to_string(result))
    }
    Error(err) -> io.println("  Error: " <> squirtle.error_to_string(err))
  }

  io.println("")

  // Example 4: Test operation (success)
  io.println("4. Test operation (success):")
  let assert Ok(doc) = squirtle.parse("{\"name\": \"John\"}")

  let patches = [
    Test(path: "/name", expect: String("John")),
    Replace(path: "/name", value: String("Jane")),
  ]

  case squirtle.apply(doc, patches) {
    Ok(result) -> {
      io.println("  Input:  {\"name\": \"John\"}")
      io.println("  Output: " <> squirtle.to_string(result))
    }
    Error(err) -> io.println("  Error: " <> squirtle.error_to_string(err))
  }

  io.println("")

  // Example 5: Test operation (failure)
  io.println("5. Test operation (failure):")
  let assert Ok(doc) = squirtle.parse("{\"name\": \"John\"}")

  let patches = [
    Test(path: "/name", expect: String("Jane")),
    Replace(path: "/name", value: String("Bob")),
  ]

  case squirtle.apply(doc, patches) {
    Ok(result) -> {
      io.println("  Input:  {\"name\": \"John\"}")
      io.println("  Output: " <> squirtle.to_string(result))
    }
    Error(err) -> io.println("  Error: " <> squirtle.error_to_string(err))
  }

  io.println("")

  // Example 6: Nested object manipulation
  io.println("6. Nested object manipulation:")
  let assert Ok(doc) =
    squirtle.parse(
      "{\"user\": {\"profile\": {\"name\": \"John\", \"age\": 30}}}",
    )

  let patches = [
    Replace(path: "/user/profile/name", value: String("Jane")),
    Add(path: "/user/profile/email", value: String("jane@example.com")),
    Remove(path: "/user/profile/age"),
  ]

  case squirtle.apply(doc, patches) {
    Ok(result) -> {
      io.println(
        "  Input:  {\"user\": {\"profile\": {\"name\": \"John\", \"age\": 30}}}",
      )
      io.println("  Output: " <> squirtle.to_string(result))
    }
    Error(err) -> io.println("  Error: " <> squirtle.error_to_string(err))
  }

  io.println("")

  // Example 7: Parsing patches from JSON
  io.println("7. Parsing patches from JSON:")
  let assert Ok(doc) = squirtle.parse("{\"count\": 0}")
  let patches_json = "[{\"op\": \"replace\", \"path\": \"/count\", \"value\": 42}]"
  let assert Ok(patches) =
    json.parse(patches_json, decode.list(squirtle.patch_decoder()))

  case squirtle.apply(doc, patches) {
    Ok(result) -> {
      io.println("  Input:  {\"count\": 0}")
      io.println("  Output: " <> squirtle.to_string(result))
    }
    Error(err) -> io.println("  Error: " <> squirtle.error_to_string(err))
  }

  io.println("")
}
