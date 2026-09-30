package hxunity.unity;

import haxe.Int64;
import hxunity.yaml.Scalars;

/**
	Helpers for Unity 64 bit ids.

	Unity object ids are signed 64 bit values. A prefab's ids are random and can
	easily exceed `2^53`, which is the largest integer a JavaScript `Number` (and
	therefore a Haxe `Int` on the JS target) represents exactly. Every id in this
	library is therefore carried as [haxe.Int64] and only converted to text for
	display, never through a `Float`.
**/
class FileId
{
	/** The `fileID: 0` Unity writes for "no reference". **/
	public static var NONE:Int64 = null;

	static var zero:Int64;

	/** Parses an id, returning `null` when [text] is not an integer. **/
	public static function parse(text:String):Int64
	{
		if (text == null) return null;
		return Scalars.tryInt64(StringTools.trim(text));
	}

	/** Parses an id, throwing a descriptive error when [text] is malformed. **/
	public static function ofString(text:String):Int64
	{
		var value = parse(text);
		if (value == null) throw 'fileID "$text" is not an integer';
		return value;
	}

	/** Decimal text of [id], or `"0"` when [id] is null. **/
	public static function toStr(id:Int64):String
	{
		return id == null ? "0" : Int64.toStr(id);
	}

	/** Decimal text of [id], or `null` when [id] is null. **/
	public static function toNullableStr(id:Int64):String
	{
		return id == null ? null : Int64.toStr(id);
	}

	/** The zero id, i.e. `fileID: 0` written as an actual id. **/
	public static function zeroId():Int64
	{
		if (zero == null) zero = Int64.ofInt(0);
		return zero;
	}

	/** True when [id] is null or equals `0`, i.e. no reference. **/
	public static function isNone(id:Int64):Bool
	{
		return id == null || Int64.compare(id, zeroId()) == 0;
	}

	/** True when [id] fits a 32 bit [Int]. **/
	public static function fitsInt(id:Int64):Bool
	{
		if (id == null) return true;
		return Int64.compare(id, Int64.ofInt(2147483647)) <= 0 && Int64.compare(id, Int64.ofInt(-2147483648)) >= 0;
	}

	/**
		Compares two ids, sorting `null` and `0` first and then numerically.

		Sorting ids as text is wrong because `-1` sorts before `-10` lexically
		only by accident and `9` sorts after `10`.
	**/
	public static function compare(a:Int64, b:Int64):Int
	{
		return Int64.compare(a == null ? zeroId() : a, b == null ? zeroId() : b);
	}
}
