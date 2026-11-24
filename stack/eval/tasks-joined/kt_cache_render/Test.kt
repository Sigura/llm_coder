enum class Color { RED, GREEN }

fun main() {
    // --- kt_lru
    check("basic") {
        val c = LruCache<String, Int>(2)
        c["a"] = 1; c["b"] = 2
        eq(1, c["a"]); eq(2, c.size); eq(listOf("b", "a"), c.keys())
    }
    check("eviction order and callback") {
        val evicted = mutableListOf<Pair<String, Int>>()
        val c = LruCache<String, Int>(2) { k, v -> evicted.add(k to v) }
        c["a"] = 1; c["b"] = 2; c["a"]; c["c"] = 3
        eq(listOf("b" to 2), evicted); eq(listOf("a", "c"), c.keys())
        eq(null, c["b"])
    }
    check("update marks recent, no eviction") {
        val evicted = mutableListOf<String>()
        val c = LruCache<String, Int>(2) { k, _ -> evicted.add(k) }
        c["a"] = 1; c["b"] = 2; c["a"] = 10
        eq(emptyList<String>(), evicted); eq(listOf("b", "a"), c.keys()); eq(10, c["a"])
        c["c"] = 3
        eq(listOf("b"), evicted)
    }
    check("contains does not touch recency") {
        val c = LruCache<String, Int>(2)
        c["a"] = 1; c["b"] = 2
        eq(true, "a" in c); eq(listOf("a", "b"), c.keys())
        c["c"] = 3
        eq(false, "a" in c)
    }
    check("remove without callback") {
        var calls = 0
        val c = LruCache<Int, String>(3) { _, _ -> calls++ }
        c[1] = "x"; c[2] = "y"
        eq("x", c.remove(1)); eq(null, c.remove(1)); eq(1, c.size); eq(0, calls)
    }
    check("nullable values") {
        val c = LruCache<String, String?>(2)
        c["n"] = null
        eq(true, "n" in c); eq(1, c.size)
    }
    check("capacity one") {
        val c = LruCache<Int, Int>(1)
        c[1] = 1; c[2] = 2
        eq(listOf(2), c.keys())
    }
    check("bad capacity") { throws<IllegalArgumentException> { LruCache<Int, Int>(0) } }
    // --- kt_tokens
    check("example") {
        val t = tokenize("status == \"open\" && (priority >= 2 || tag != 'x\\'y')")
        eq(listOf(
            Token.Ident("status", 0), Token.Op("==", 7), Token.Str("open", 10), Token.Op("&&", 17),
            Token.Paren(true, 20), Token.Ident("priority", 21), Token.Op(">=", 30), Token.Num(2.0, 33),
            Token.Op("||", 35), Token.Ident("tag", 38), Token.Op("!=", 42), Token.Str("x'y", 45), Token.Paren(false, 51)
        ), t)
    }
    check("negative numbers") {
        eq(listOf(Token.Num(-1.5, 0)), tokenize("-1.5"))
        eq(listOf(Token.Ident("a", 0), Token.Op("<", 2), Token.Num(-3.0, 4)), tokenize("a < -3"))
        eq(listOf(Token.Paren(true, 0), Token.Num(-2.0, 1), Token.Paren(false, 3)), tokenize("(-2)"))
    }
    check("minus not allowed after value") {
        val e = runCatching { tokenize("a -1") }.exceptionOrNull()
        eq(true, e is TokenizeException); eq(2, (e as TokenizeException).pos)
    }
    check("ops longest match") {
        eq(listOf("!", "!=", "<", "<=", ">", ">="), tokenize("! != < <= > >=").map { (it as Token.Op).symbol })
    }
    check("escapes and newline") {
        eq(listOf(Token.Str("a\nb\\c\"", 0)), tokenize("\"a\\nb\\\\c\\\"\""))
    }
    check("dotted ident and whitespace") {
        eq(listOf(Token.Ident("user.name_2", 1), Token.Op("==", 14), Token.Ident("x", 18)), tokenize("\tuser.name_2 \n== \tx"))
    }
    check("empty") { eq(emptyList<Token>(), tokenize("  ")) }
    check("errors") {
        for ((src, pos) in listOf("a = b" to 2, "a & b" to 2, "'open" to 0, "x == .5" to 5, "x == 5." to 5, "a#" to 1)) {
            val e = runCatching { tokenize(src) }.exceptionOrNull()
            if (e !is TokenizeException) throw AssertionError("$src: expected TokenizeException, got $e")
            if (e.pos != pos) throw AssertionError("$src: expected pos $pos, got ${e.pos}")
        }
    }
    // --- kt_render
    check("scalars") {
        eq("null", toJson(null)); eq("true", toJson(true)); eq("42", toJson(42)); eq("9000000000", toJson(9000000000L))
        eq("2.0", toJson(2.0)); eq("1.5", toJson(1.5f)); eq("\"RED\"", toJson(Color.RED))
    }
    check("escapes") {
        eq("\"a\\\"b\\\\c\\nd\\te\\u0001é\"", toJson("a\"b\\c\nd\te\u0001é"))
        eq("\"\\b\\f\\r\\u001f\"", toJson("\b\u000c\r\u001f"))
    }
    check("compact nested") {
        val v = linkedMapOf("a" to 1, "b" to listOf(1, null, "x"), "c" to mapOf<String, Any>(), "d" to emptyList<Int>())
        eq("{\"a\":1,\"b\":[1,null,\"x\"],\"c\":{},\"d\":[]}", toJson(v))
    }
    check("array") { eq("[1,2]", toJson(arrayOf(1, 2))) }
    check("pretty") {
        val v = linkedMapOf("name" to "x", "tags" to listOf("a", "b"), "empty" to emptyMap<String, Int>(),
                            "nested" to mapOf("k" to listOf(mapOf("z" to 1))))
        val expected = """
{
  "name": "x",
  "tags": [
    "a",
    "b"
  ],
  "empty": {},
  "nested": {
    "k": [
      {
        "z": 1
      }
    ]
  }
}""".trimStart('\n')
        eq(expected, toJson(v, 2))
    }
    check("bad key") { throws<IllegalArgumentException> { toJson(mapOf(1 to 2)) } }
    check("nan") { throws<IllegalArgumentException> { toJson(Double.NaN) } }
    check("unsupported") { throws<IllegalArgumentException> { toJson(Any()) } }
    // --- integration
    check("token json") {
        val c = TokenJsonCache(2)
        eq("[{\"type\":\"ident\",\"pos\":0,\"value\":\"a.b\"},{\"type\":\"op\",\"pos\":4,\"value\":\">=\"}," +
           "{\"type\":\"num\",\"pos\":7,\"value\":-2.0},{\"type\":\"op\",\"pos\":10,\"value\":\"&&\"}," +
           "{\"type\":\"paren\",\"pos\":13,\"value\":\"(\"},{\"type\":\"str\",\"pos\":14,\"value\":\"x\\n\\\"\"}," +
           "{\"type\":\"paren\",\"pos\":21,\"value\":\")\"}]",
           c.json("a.b >= -2 && (\"x\\n\\\"\")"))
        eq(1, c.misses)
    }
    check("pretty and cached across indents") {
        val c = TokenJsonCache(2)
        eq("[\n  {\n    \"type\": \"op\",\n    \"pos\": 0,\n    \"value\": \"!\"\n  }\n]", c.json("!", 2))
        eq("[{\"type\":\"op\",\"pos\":0,\"value\":\"!\"}]", c.json("!"))
        eq(1, c.misses)
        eq("[]", c.json(" "))
        eq(2, c.misses)
    }
    check("errors cached") {
        val c = TokenJsonCache(3)
        eq("{\"error\":\"tokenize\",\"pos\":2}", c.json("a = b"))
        eq("{\n    \"error\": \"tokenize\",\n    \"pos\": 2\n}", c.json("a = b", 4))
        eq(1, c.misses)
    }
    check("lru eviction") {
        val c = TokenJsonCache(2)
        c.json("a"); c.json("b"); c.json("a"); c.json("c")
        eq(listOf("b"), c.evicted)
        c.json("b")
        eq(listOf("b", "a"), c.evicted)
        eq(4, c.misses)
        c.json("c")
        eq(4, c.misses)
    }
    check("cache capacity") { throws<IllegalArgumentException> { TokenJsonCache(0) } }
    finish()
}
