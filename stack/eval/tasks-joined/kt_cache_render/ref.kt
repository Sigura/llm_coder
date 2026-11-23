class LruCache<K, V>(val capacity: Int, private val onEvict: (K, V) -> Unit = { _, _ -> }) {
    private val map = LinkedHashMap<K, V>(16, 0.75f, false)

    init {
        require(capacity >= 1) { "capacity must be >= 1" }
    }

    val size: Int get() = map.size

    operator fun get(key: K): V? {
        if (!map.containsKey(key)) return null
        @Suppress("UNCHECKED_CAST")
        val v = map.remove(key) as V
        map[key] = v
        return v
    }

    operator fun set(key: K, value: V) {
        if (map.containsKey(key)) {
            map.remove(key)
            map[key] = value
            return
        }
        map[key] = value
        if (map.size > capacity) {
            val k = map.keys.first()
            @Suppress("UNCHECKED_CAST")
            val v = map.remove(k) as V
            onEvict(k, v)
        }
    }

    fun remove(key: K): V? = map.remove(key)

    fun keys(): List<K> = map.keys.toList()

    operator fun contains(key: K): Boolean = map.containsKey(key)
}

sealed class Token {
    abstract val pos: Int
    data class Ident(val name: String, override val pos: Int) : Token()
    data class Str(val value: String, override val pos: Int) : Token()
    data class Num(val value: Double, override val pos: Int) : Token()
    data class Op(val symbol: String, override val pos: Int) : Token()
    data class Paren(val open: Boolean, override val pos: Int) : Token()
}

class TokenizeException(message: String, val pos: Int) : Exception(message)

private val OPS = listOf("==", "!=", "<=", ">=", "&&", "||", "<", ">", "!")

fun tokenize(input: String): List<Token> {
    val out = mutableListOf<Token>()
    var i = 0
    while (i < input.length) {
        val c = input[i]
        when {
            c == ' ' || c == '\t' || c == '\n' -> i++
            c.isLetter() && c.code < 128 || c == '_' -> {
                val start = i
                i++
                while (i < input.length && (input[i].isLetterOrDigit() && input[i].code < 128 || input[i] == '_' || input[i] == '.')) i++
                out.add(Token.Ident(input.substring(start, i), start))
            }
            c.isDigit() || c == '-' -> {
                val start = i
                if (c == '-') {
                    val prev = out.lastOrNull()
                    val ok = prev == null || prev is Token.Op || (prev is Token.Paren && prev.open)
                    if (!ok || i + 1 >= input.length || !input[i + 1].isDigit()) throw TokenizeException("unexpected -", i)
                    i++
                }
                while (i < input.length && input[i].isDigit()) i++
                if (i < input.length && input[i] == '.') {
                    i++
                    if (i >= input.length || !input[i].isDigit()) throw TokenizeException("bad number", start)
                    while (i < input.length && input[i].isDigit()) i++
                }
                out.add(Token.Num(input.substring(start, i).toDouble(), start))
            }
            c == '"' || c == '\'' -> {
                val start = i
                val sb = StringBuilder()
                i++
                while (true) {
                    if (i >= input.length) throw TokenizeException("unterminated string", start)
                    val d = input[i]
                    if (d == c) { i++; break }
                    if (d == '\\') {
                        if (i + 1 >= input.length) throw TokenizeException("unterminated string", start)
                        val e = input[i + 1]
                        sb.append(if (e == 'n') '\n' else e)
                        i += 2
                    } else {
                        sb.append(d); i++
                    }
                }
                out.add(Token.Str(sb.toString(), start))
            }
            c == '(' || c == ')' -> { out.add(Token.Paren(c == '(', i)); i++ }
            else -> {
                val op = OPS.firstOrNull { input.startsWith(it, i) } ?: throw TokenizeException("unexpected '$c'", i)
                out.add(Token.Op(op, i))
                i += op.length
            }
        }
    }
    return out
}

fun toJson(value: Any?, indent: Int = 0): String {
    val sb = StringBuilder()
    write(sb, value, indent, 0)
    return sb.toString()
}

private fun escape(s: String): String {
    val sb = StringBuilder("\"")
    for (c in s) {
        when {
            c == '"' -> sb.append("\\\"")
            c == '\\' -> sb.append("\\\\")
            c == '\b' -> sb.append("\\b")
            c == '\u000c' -> sb.append("\\f")
            c == '\n' -> sb.append("\\n")
            c == '\r' -> sb.append("\\r")
            c == '\t' -> sb.append("\\t")
            c < ' ' -> sb.append("\\u%04x".format(c.code))
            else -> sb.append(c)
        }
    }
    return sb.append('"').toString()
}

private fun write(sb: StringBuilder, v: Any?, indent: Int, level: Int) {
    when (v) {
        null -> sb.append("null")
        is Boolean, is Int, is Long -> sb.append(v.toString())
        is Double -> {
            require(v.isFinite()) { "non-finite double" }
            sb.append(v.toString())
        }
        is Float -> {
            require(v.isFinite()) { "non-finite float" }
            sb.append(v.toString())
        }
        is String -> sb.append(escape(v))
        is Enum<*> -> sb.append(escape(v.name))
        is Map<*, *> -> {
            val entries = v.entries.map { (k, x) ->
                require(k is String) { "map keys must be strings" }
                k to x
            }
            container(sb, '{', '}', entries, indent, level) { (k, x) ->
                sb.append(escape(k)).append(if (indent > 0) ": " else ":")
                write(sb, x, indent, level + 1)
            }
        }
        is List<*> -> container(sb, '[', ']', v, indent, level) { write(sb, it, indent, level + 1) }
        is Array<*> -> container(sb, '[', ']', v.toList(), indent, level) { write(sb, it, indent, level + 1) }
        else -> throw IllegalArgumentException("unsupported type ${v::class}")
    }
}

private fun <T> container(sb: StringBuilder, open: Char, close: Char, items: List<T>, indent: Int, level: Int,
                          item: (T) -> Unit) {
    sb.append(open)
    if (items.isEmpty()) {
        sb.append(close)
        return
    }
    items.forEachIndexed { i, x ->
        if (i > 0) sb.append(',')
        if (indent > 0) sb.append('\n').append(" ".repeat(indent * (level + 1)))
        item(x)
    }
    if (indent > 0) sb.append('\n').append(" ".repeat(indent * level))
    sb.append(close)
}

class TokenJsonCache(capacity: Int) {
    private val _evicted = mutableListOf<String>()
    val evicted: List<String> get() = _evicted
    var misses = 0
        private set
    private val cache = LruCache<String, Any>(capacity) { k, _ -> _evicted.add(k) }

    fun json(filter: String, indent: Int = 0): String {
        val hit = filter in cache
        val v = if (hit) cache[filter]!! else {
            misses++
            val r: Any = try {
                tokenize(filter).map { t ->
                    when (t) {
                        is Token.Ident -> linkedMapOf("type" to "ident", "pos" to t.pos, "value" to t.name)
                        is Token.Str -> linkedMapOf("type" to "str", "pos" to t.pos, "value" to t.value)
                        is Token.Num -> linkedMapOf("type" to "num", "pos" to t.pos, "value" to t.value)
                        is Token.Op -> linkedMapOf("type" to "op", "pos" to t.pos, "value" to t.symbol)
                        is Token.Paren -> linkedMapOf("type" to "paren", "pos" to t.pos, "value" to if (t.open) "(" else ")")
                    }
                }
            } catch (e: TokenizeException) {
                linkedMapOf("error" to "tokenize", "pos" to e.pos)
            }
            cache[filter] = r
            r
        }
        return toJson(v, indent)
    }
}
