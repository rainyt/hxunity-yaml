package hxunity.types;

/**
	Number formatting that matches what Unity writes.

	A prefab that is read and written back should not gain a `.0` on every
	integer, and Unity itself omits it: `-0.02`, `0`, `10`, `0.7071068`.
**/
class Numbers
{
	/**
		Formats [value] the way Unity would.

		Whole numbers are written without a decimal part, so `1` stays `1` and not
		`1.0`. Every other value uses Haxe's shortest exact representation, which is
		what [Std.string] produces and is the same choice Unity's own writer makes
		for floats.
	**/
	public static function format(value:Float):String
	{
		if (Math.isNaN(value)) return ".nan";
		if (value == Math.POSITIVE_INFINITY) return ".inf";
		if (value == Math.NEGATIVE_INFINITY) return "-.inf";
		if (value == 0)
		{
			// Unity writes quaternion and euler-hint components as `-0` all the
			// time, and that negative zero has to survive a read/write cycle
			// because Unity's own diff would otherwise show the change.
			return isNegativeZero(value) ? "-0" : "0";
		}
		if (value == Math.ffloor(value) && Math.abs(value) < 1e15)
		{
			return Std.string(Std.int(value));
		}
		var plain = Std.string(value);
		return plain.indexOf("e") < 0 ? plain : expandExponent(plain);
	}

	/** True when [value] is a negative zero, which `value < 0` does not catch. **/
	public static function isNegativeZero(value:Float):Bool
	{
		return value == 0 && 1 / value == Math.NEGATIVE_INFINITY;
	}

	/**
		Rewrites `1e-005` as `0.00001`.

		Unity's own writer never emits exponent notation, and a rounded value such
		as `0.00001` would otherwise read back through [Std.string] as `1e-005`,
		which is the same number but not the same file.
	**/
	static function expandExponent(text:String):String
	{
		var at = text.indexOf("e");
		if (at < 0) return text;
		var mantissa = text.substring(0, at);
		var exponent = Std.parseInt(text.substring(at + 1));
		if (exponent == null) return text;

		var negative = StringTools.startsWith(mantissa, "-");
		if (negative) mantissa = mantissa.substr(1);
		var dot = mantissa.indexOf(".");
		var digits = dot < 0 ? mantissa : mantissa.substring(0, dot) + mantissa.substring(dot + 1);
		// Position of the decimal point after shifting by the exponent.
		var point = (dot < 0 ? mantissa.length : dot) + exponent;

		var body:String;
		if (point <= 0)
		{
			body = "0." + zeroes(-point) + digits;
		}
		else if (point >= digits.length)
		{
			body = digits + zeroes(point - digits.length) + ".0";
		}
		else
		{
			body = digits.substring(0, point) + "." + digits.substring(point);
		}
		if (StringTools.endsWith(body, ".0")) body = body.substr(0, body.length - 2);
		return negative ? "-" + body : body;
	}

	/** [count] zero characters, used to rebuild a decimal from an exponent. **/
	static function zeroes(count:Int):String
	{
		if (count <= 0) return "";
		var sb = new StringBuf();
		var i = 0;
		while (i < count)
		{
			sb.add("0");
			i++;
		}
		return sb.toString();
	}
}
