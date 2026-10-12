package hxunity.yaml;

import haxe.Int64;

/**
	A self contained pseudorandom source, shared by everything in the library
	that has to invent an id: `UnityDocumentSet.newFileId` and
	`hxunity.unity.AssetGuid`.

	`Std.random` is deliberately not used. The standard generator is not seeded
	on every target, and on Neko an unseeded `Std.random` throws instead of
	returning a value, which made every edit that creates an object fail. A
	generator owned here behaves the same on every target, which is what lets a
	test assert that ids and GUIDs are unique across a batch rather than hoping
	the platform's generator is up to it.

	The state is 31 bits and is kept at least 1, so the xorshift can never
	reach its zero lockup.
**/
class Xorshift
{
	/** Current state; 1 based so the generator never reaches the zero lockup. **/
	static var seed:Int = 0;

	/** Sets the state, which makes a run reproducible. `0` means "seed from the clock". **/
	public static function reseed(state:Int):Void
	{
		seed = state <= 0 ? 0 : state;
	}

	/**
		Next 31 bit value, always at least 1.

		Two of these are joined by [int64] to make a 62 bit id, so callers that
		need more entropy draw more of them.
	**/
	public static function bits():Int
	{
		if (seed == 0)
		{
			// Seed lazily from the clock so repeated runs differ, and keep the
			// value inside the 31 bit state the generator requires.
			var fromClock = Std.int(Date.now().getTime() % 2147483646);
			if (fromClock < 0) fromClock = -fromClock;
			seed = fromClock + 1;
		}
		var x = seed;
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		x &= 0x7FFFFFFF;
		if (x == 0) x = 1;
		seed = x;
		return x;
	}

	/**
		Positive 64 bit value below `2^62`, the range Unity file ids live in.

		Two 31 bit halves are drawn and joined with [Int64.add] rather than
		[Int64.ofInt] on a wide value, because `Int64.ofInt` overflows above
		`2^30` on the JavaScript target, where an [Int] is a double.
	**/
	public static function int64():Int64
	{
		var high = bits();
		var low = bits();
		return Int64.add(Int64.mul(Int64.ofInt(high), Int64.ofInt(1073741824)), Int64.ofInt(low));
	}

	/**
		[count] random bytes.

		Used for GUIDs: a GUID is 128 bits of entropy, so it needs four times the
		width of a file id and is filled byte by byte from [bits].
	**/
	public static function bytes(count:Int, ?into:haxe.io.Bytes):haxe.io.Bytes
	{
		var out = into == null ? haxe.io.Bytes.alloc(count) : into;
		var index = 0;
		while (index < count)
		{
			var value = bits();
			var chunk = count - index;
			if (chunk > 3) chunk = 3;
			for (i in 0...chunk)
			{
				out.set(index + i, (value >>> (8 * i)) & 0xFF);
			}
			index += chunk;
		}
		return out;
	}
}
