import java.util.TreeMap

private val WEEKS = Regex("P([0-9]+)W")
private val DHMS = Regex("P(?:([0-9]+)D)?(?:T(?:([0-9]+)H)?(?:([0-9]+)M)?(?:([0-9]+)S)?)?")

fun parseIsoDuration(s: String): Long {
    WEEKS.matchEntire(s)?.let { return it.groupValues[1].toLong() * 7 * 86400 }
    val m = DHMS.matchEntire(s) ?: throw IllegalArgumentException("bad duration $s")
    val (d, h, mi, se) = m.destructured
    if (d.isEmpty() && h.isEmpty() && mi.isEmpty() && se.isEmpty()) throw IllegalArgumentException("empty $s")
    if (s.contains('T') && h.isEmpty() && mi.isEmpty() && se.isEmpty()) throw IllegalArgumentException("empty T $s")
    fun n(x: String) = if (x.isEmpty()) 0L else x.toLong()
    return n(d) * 86400 + n(h) * 3600 + n(mi) * 60 + n(se)
}

fun formatIsoDuration(seconds: Long): String {
    require(seconds >= 0) { "negative" }
    if (seconds == 0L) return "PT0S"
    val d = seconds / 86400
    val h = seconds % 86400 / 3600
    val m = seconds % 3600 / 60
    val s = seconds % 60
    val sb = StringBuilder("P")
    if (d > 0) sb.append(d).append('D')
    if (h > 0 || m > 0 || s > 0) {
        sb.append('T')
        if (h > 0) sb.append(h).append('H')
        if (m > 0) sb.append(m).append('M')
        if (s > 0) sb.append(s).append('S')
    }
    return sb.toString()
}

class IntervalSet {
    private val map = TreeMap<Long, Long>()

    fun add(start: Long, end: Long) {
        require(start < end)
        var s = start
        var e = end
        val lower = map.floorEntry(s)
        if (lower != null && lower.value >= s) {
            s = lower.key
            e = maxOf(e, lower.value)
        }
        while (true) {
            val next = map.ceilingEntry(s) ?: break
            if (next.key > e) break
            e = maxOf(e, next.value)
            map.remove(next.key)
        }
        map[s] = e
    }

    fun remove(start: Long, end: Long) {
        require(start < end)
        val lower = map.lowerEntry(start)
        if (lower != null && lower.value > start) {
            map[lower.key] = start
            if (lower.value > end) map[end] = lower.value
        }
        while (true) {
            val next = map.ceilingEntry(start) ?: break
            if (next.key >= end) break
            map.remove(next.key)
            if (next.value > end) map[end] = next.value
        }
    }

    operator fun contains(x: Long): Boolean {
        val e = map.floorEntry(x) ?: return false
        return x < e.value
    }

    fun overlaps(start: Long, end: Long): Boolean {
        require(start < end)
        val lower = map.lowerEntry(end) ?: return false
        return lower.value > start
    }

    fun intervals(): List<Pair<Long, Long>> = map.entries.map { it.key to it.value }

    val total: Long get() = map.entries.sumOf { it.value - it.key }

    fun gaps(from: Long, to: Long): List<Pair<Long, Long>> {
        require(from <= to)
        val out = mutableListOf<Pair<Long, Long>>()
        var cur = from
        for ((s, e) in map) {
            if (e <= cur) continue
            if (s >= to) break
            if (s > cur) out.add(cur to s)
            cur = maxOf(cur, e)
            if (cur >= to) break
        }
        if (cur < to) out.add(cur to to)
        return out
    }
}

class TokenBucket(val capacity: Int, val refillMillis: Long, private val clock: () -> Long) {
    private var tokens: Int
    private var t0: Long

    init {
        require(capacity >= 1 && refillMillis >= 1)
        tokens = capacity
        t0 = clock()
    }

    private fun refill() {
        val now = clock()
        val k = (now - t0) / refillMillis
        t0 += k * refillMillis
        if (tokens.toLong() + k >= capacity) {
            tokens = capacity
            t0 = now
        } else {
            tokens += k.toInt()
        }
    }

    fun tryAcquire(n: Int = 1): Boolean {
        require(n in 1..capacity)
        refill()
        if (tokens < n) return false
        tokens -= n
        return true
    }

    fun available(): Int {
        refill()
        return tokens
    }
}

sealed class BookingResult {
    data class Booked(val id: Int) : BookingResult()
    data class Conflict(val withIds: List<Int>) : BookingResult()
    object RateLimited : BookingResult()
    data class Invalid(val reason: String) : BookingResult()
}

class BookingSystem(private val clock: () -> Long) {
    private class Booking(val id: Int, val user: String, val room: String, val start: Long, val end: Long)

    private val buckets = HashMap<String, TokenBucket>()
    private val rooms = HashMap<String, IntervalSet>()
    private val byId = LinkedHashMap<Int, Booking>()
    private var nextId = 1

    fun book(user: String, room: String, start: Long, duration: String): BookingResult {
        val secs = try { parseIsoDuration(duration) } catch (e: IllegalArgumentException) { -1L }
        if (secs <= 0 || secs > 86400) return BookingResult.Invalid("duration")
        val bucket = buckets.getOrPut(user) { TokenBucket(3, 60_000, clock) }
        if (!bucket.tryAcquire()) return BookingResult.RateLimited
        val end = start + secs
        val set = rooms.getOrPut(room) { IntervalSet() }
        if (set.overlaps(start, end)) {
            val ids = byId.values.filter { it.room == room && it.start < end && start < it.end }.map { it.id }.sorted()
            return BookingResult.Conflict(ids)
        }
        set.add(start, end)
        val id = nextId++
        byId[id] = Booking(id, user, room, start, end)
        return BookingResult.Booked(id)
    }

    fun cancel(user: String, id: Int): Boolean {
        val b = byId[id] ?: return false
        if (b.user != user) return false
        byId.remove(id)
        rooms.getValue(b.room).remove(b.start, b.end)
        return true
    }

    fun bookings(room: String): List<Triple<Int, Long, Long>> =
        byId.values.filter { it.room == room }.sortedBy { it.start }.map { Triple(it.id, it.start, it.end) }

    fun free(room: String, from: Long, to: Long): List<Pair<Long, Long>> =
        (rooms[room] ?: IntervalSet()).gaps(from, to)
}
