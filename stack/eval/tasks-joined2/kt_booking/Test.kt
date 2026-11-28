class FakeClock(var now: Long = 1_000_000L) {
    val fn: () -> Long = { now }
}

fun main() {
    // --- duration
    check("parse forms") {
        eq(86400L, parseIsoDuration("P1D"))
        eq(3600L, parseIsoDuration("PT1H"))
        eq(90061L, parseIsoDuration("P1DT1H1M1S"))
        eq(5400L, parseIsoDuration("PT90M"))
        eq(1209600L, parseIsoDuration("P2W"))
        eq(0L, parseIsoDuration("PT0S"))
        eq(3601L, parseIsoDuration("PT1H1S"))
        eq(86460L, parseIsoDuration("P1DT1M"))
        eq(7L, parseIsoDuration("PT007S"))
    }
    check("parse invalid") {
        for (s in listOf("", "P", "PT", "P1H", "PT1D", "P1W2D", "P1WT1H", "p1d", "PT1.5S", "P-1D", "P1D1D", "PT1M1H",
                "1D", "P1DT", "PT1H ", " PT1H", "P1Y", "PT+1S", "P1DT1S1M")) {
            throws<IllegalArgumentException> { parseIsoDuration(s) }
        }
    }
    check("format") {
        eq("P1DT1H1M1S", formatIsoDuration(90061))
        eq("P1D", formatIsoDuration(86400))
        eq("PT1H30M", formatIsoDuration(5400))
        eq("PT0S", formatIsoDuration(0))
        eq("PT59S", formatIsoDuration(59))
        eq("P14D", formatIsoDuration(1209600))
        eq("P2DT5S", formatIsoDuration(172805))
        throws<IllegalArgumentException> { formatIsoDuration(-1) }
    }
    check("roundtrip") {
        for (n in listOf(1L, 60L, 61L, 3599L, 3600L, 86399L, 86401L, 999999L)) eq(n, parseIsoDuration(formatIsoDuration(n)))
    }

    // --- intervals
    check("add merges overlapping and touching") {
        val s = IntervalSet()
        s.add(10, 20); s.add(30, 40); s.add(20, 25); s.add(5, 8)
        eq(listOf(5L to 8L, 10L to 25L, 30L to 40L), s.intervals())
        s.add(7, 31)
        eq(listOf(5L to 40L), s.intervals())
        eq(35L, s.total)
        s.add(1, 2); s.add(0, 100)
        eq(listOf(0L to 100L), s.intervals())
    }
    check("remove splits") {
        val s = IntervalSet()
        s.add(0, 100)
        s.remove(10, 20)
        eq(listOf(0L to 10L, 20L to 100L), s.intervals())
        s.remove(5, 30); s.remove(90, 200); s.remove(-5, 1)
        eq(listOf(1L to 5L, 30L to 90L), s.intervals())
        s.remove(200, 300)
        eq(64L, s.total)
        s.remove(0, 1000)
        eq(emptyList<Pair<Long, Long>>(), s.intervals()); eq(0L, s.total)
    }
    check("contains and overlaps are half-open") {
        val s = IntervalSet()
        s.add(10, 20)
        eq(true, 10L in s); eq(true, 19L in s); eq(false, 20L in s); eq(false, 9L in s)
        eq(false, s.overlaps(20, 30)); eq(false, s.overlaps(0, 10)); eq(true, s.overlaps(19, 21))
        eq(true, s.overlaps(0, 11)); eq(true, s.overlaps(12, 13)); eq(true, s.overlaps(0, 100))
        s.add(30, 40)
        eq(false, s.overlaps(20, 30)); eq(true, s.overlaps(20, 31))
    }
    check("gaps") {
        val s = IntervalSet()
        s.add(10, 20); s.add(30, 40)
        eq(listOf(0L to 10L, 20L to 30L, 40L to 50L), s.gaps(0, 50))
        eq(listOf(20L to 30L), s.gaps(15, 35))
        eq(emptyList<Pair<Long, Long>>(), s.gaps(12, 18))
        eq(emptyList<Pair<Long, Long>>(), s.gaps(5, 5))
        eq(listOf(22L to 25L), s.gaps(22, 25))
        eq(listOf(40L to 41L), s.gaps(30, 41))
        throws<IllegalArgumentException> { s.gaps(5, 4) }
    }
    check("interval argument checks") {
        val s = IntervalSet()
        throws<IllegalArgumentException> { s.add(5, 5) }
        throws<IllegalArgumentException> { s.remove(6, 5) }
        throws<IllegalArgumentException> { s.overlaps(1, 1) }
    }

    // --- token bucket
    check("bucket basics") {
        val c = FakeClock()
        val b = TokenBucket(3, 1000, c.fn)
        eq(3, b.available())
        eq(true, b.tryAcquire()); eq(true, b.tryAcquire(2)); eq(false, b.tryAcquire())
        c.now += 999; eq(0, b.available())
        c.now += 1; eq(1, b.available())
        c.now += 2500; eq(3, b.available())
    }
    check("bucket keeps partial progress") {
        val c = FakeClock()
        val b = TokenBucket(5, 1000, c.fn)
        eq(true, b.tryAcquire(5))
        c.now += 1500; eq(1, b.available())
        c.now += 500; eq(2, b.available())
        c.now += 700; eq(true, b.tryAcquire(2)); eq(false, b.tryAcquire())
        c.now += 300; eq(1, b.available())
    }
    check("bucket full resets reference") {
        val c = FakeClock()
        val b = TokenBucket(2, 1000, c.fn)
        c.now += 10_500
        eq(true, b.tryAcquire())
        c.now += 600
        // the bucket was full at the last call: t0 moved to that call, so 600 ms are not enough
        eq(1, b.available())
        c.now += 400; eq(2, b.available())
    }
    check("bucket failed acquire takes nothing") {
        val c = FakeClock()
        val b = TokenBucket(3, 100, c.fn)
        eq(true, b.tryAcquire(2)); eq(false, b.tryAcquire(2)); eq(1, b.available())
        c.now += 100; eq(true, b.tryAcquire(2)); eq(0, b.available())
    }
    check("bucket argument checks") {
        val c = FakeClock()
        throws<IllegalArgumentException> { TokenBucket(0, 100, c.fn) }
        throws<IllegalArgumentException> { TokenBucket(1, 0, c.fn) }
        val b = TokenBucket(2, 100, c.fn)
        throws<IllegalArgumentException> { b.tryAcquire(0) }
        throws<IllegalArgumentException> { b.tryAcquire(3) }
        eq(2, b.available())
    }

    // --- integration
    val h = 3600L
    check("book and conflict") {
        val c = FakeClock()
        val sys = BookingSystem(c.fn)
        eq(BookingResult.Booked(1), sys.book("ann", "blue", 10 * h, "PT1H"))
        eq(BookingResult.Booked(2), sys.book("bob", "blue", 11 * h, "PT30M"))
        eq(BookingResult.Booked(3), sys.book("bob", "red", 10 * h, "PT2H"))
        eq(BookingResult.Conflict(listOf(1, 2)), sys.book("cy", "blue", 10 * h + 1800, "PT1H"))
        eq(BookingResult.Booked(4), sys.book("cy", "blue", 11 * h + 1800, "PT15M"))
        eq(listOf(Triple(1, 10 * h, 11 * h), Triple(2, 11 * h, 11 * h + 1800), Triple(4, 11 * h + 1800, 11 * h + 2700)),
            sys.bookings("blue"))
        eq(emptyList<Triple<Int, Long, Long>>(), sys.bookings("green"))
    }
    check("invalid durations use no token") {
        val c = FakeClock()
        val sys = BookingSystem(c.fn)
        for (d in listOf("PT0S", "P1DT1S", "P1W", "bogus", "PT", "P2D")) eq(BookingResult.Invalid("duration"), sys.book("ann", "r", 0, d))
        eq(BookingResult.Booked(1), sys.book("ann", "r", 0, "P1D"))
        eq(BookingResult.Booked(2), sys.book("ann", "r", 86400, "PT86400S"))
        eq(BookingResult.Booked(3), sys.book("ann", "r", 2 * 86400, "PT1S"))
        eq(BookingResult.RateLimited, sys.book("ann", "r", 5 * 86400, "PT1S"))
    }
    check("rate limit per user, conflicts use tokens") {
        val c = FakeClock()
        val sys = BookingSystem(c.fn)
        eq(BookingResult.Booked(1), sys.book("ann", "r", 0, "PT1H"))
        eq(BookingResult.Conflict(listOf(1)), sys.book("ann", "r", 0, "PT1H"))
        eq(BookingResult.Conflict(listOf(1)), sys.book("ann", "r", 1800, "PT1H"))
        eq(BookingResult.RateLimited, sys.book("ann", "r", 5 * h, "PT1H"))
        eq(BookingResult.Booked(2), sys.book("bob", "r", 5 * h, "PT1H"))
        c.now += 59_999
        eq(BookingResult.RateLimited, sys.book("ann", "r", 7 * h, "PT1H"))
        c.now += 1
        eq(BookingResult.Booked(3), sys.book("ann", "r", 7 * h, "PT1H"))
        eq(BookingResult.RateLimited, sys.book("ann", "r", 9 * h, "PT1H"))
    }
    check("cancel and free") {
        val c = FakeClock()
        val sys = BookingSystem(c.fn)
        sys.book("ann", "r", 10 * h, "PT1H"); sys.book("bob", "r", 11 * h, "PT1H"); sys.book("ann", "r", 14 * h, "PT2H")
        eq(listOf(8 * h to 10 * h, 12 * h to 14 * h, 16 * h to 18 * h), sys.free("r", 8 * h, 18 * h))
        eq(false, sys.cancel("ann", 2)); eq(false, sys.cancel("ann", 99))
        eq(true, sys.cancel("bob", 2)); eq(false, sys.cancel("bob", 2))
        eq(listOf(8 * h to 10 * h, 11 * h to 14 * h, 16 * h to 18 * h), sys.free("r", 8 * h, 18 * h))
        eq(listOf(Triple(1, 10 * h, 11 * h), Triple(3, 14 * h, 16 * h)), sys.bookings("r"))
        c.now += 120_000
        eq(BookingResult.Booked(4), sys.book("cy", "r", 11 * h, "PT2H"))
        eq(listOf(10 * h to 13 * h), listOf(sys.bookings("r")[0].second to sys.bookings("r")[1].third))
        eq(listOf(0L to 5L), sys.free("unknown", 0, 5))
        throws<IllegalArgumentException> { sys.free("unknown", 5, 0) }
        throws<IllegalArgumentException> { sys.free("r", 5, 0) }
    }
    check("cancel keeps neighbours booked") {
        val c = FakeClock()
        val sys = BookingSystem(c.fn)
        sys.book("ann", "r", 0, "PT1H"); sys.book("ann", "r", h, "PT1H"); sys.book("ann", "r", 2 * h, "PT1H")
        eq(true, sys.cancel("ann", 2))
        eq(listOf(h to 2 * h), sys.free("r", 0, 3 * h))
        eq(BookingResult.Conflict(listOf(1, 3)), sys.book("bob", "r", h - 1, "PT1H2S"))
        eq(BookingResult.Booked(4), sys.book("bob", "r", h, "PT1H"))
    }
    finish()
}
