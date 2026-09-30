package hxunity.yaml;

import haxe.Int64;

/**
	Scalar text interpretation shared by the parser, the node accessors and the
	writer.

	Everything here is deliberately conservative: a value is only treated as a
	number when a plain (unquoted) scalar matches a Unity number exactly, and
	64 bit ids are kept as text so nothing is lost. Unity writes ids such as
	`8601872862307532784` which do not survive a [Float], and on JavaScript a
	Haxe `Int` is a double, so [tryInt64] is the only safe number accessor for
	ids.
**/
class Scalars
{
	static var boolTrue:Map<String, Bool>;
	static var boolFalse:Map<String, Bool>;

	static function ensureBools():Void
	{
		if (boolTrue != null) return;
		boolTrue = new Map();
		boolFalse = new Map();
		for (v in ["true", "True", "TRUE", "yes", "Yes", "YES", "on", "On", "ON", "y", "Y"])
		{
			boolTrue.set(v, true);
		}
		for (v in ["false", "False", "FALSE", "no", "No", "NO", "off", "Off", "OFF", "n", "N"])
		{
			boolFalse.set(v, true);
		}
	}

	/** True when [text] is YAML 1.1 or Unity boolean `true`. **/
	static function isTrue(text:String):Bool
	{
		ensureBools();
		return boolTrue.exists(text);
	}

	/** True when [text] is YAML 1.1 or Unity boolean `false`. **/
	static function isFalse(text:String):Bool
	{
		ensureBools();
		return boolFalse.exists(text);
	}

	/** Interpreted bool, throwing when [text] is not a boolean keyword. **/
	public static function toBool(text:String):Bool
	{
		var v = tryBool(text);
		if (v == null) throw new YamlError('"$text" is not a boolean');
		return v;
	}

	/**
		Interpreted bool, or `null` when [text] is not a boolean.

		Handles `true` / `false` as YAML 1.1 spells them, plus the `1` / `0` Unity
		actually writes for every boolean field (`m_Enabled: 1`). Recognising the
		numeric form is what lets `m_IsActive: 0` read as false instead of as an
		unknown value.
	**/
	public static function tryBool(text:String):Null<Bool>
	{
		ensureBools();
		if (boolTrue.exists(text)) return true;
		if (boolFalse.exists(text)) return false;
		if (text == "1") return true;
		if (text == "0") return false;
		return null;
	}

	/** True when [text] is a quoted scalar. **/
	public static function isQuoted(text:String):Bool
	{
		if (text.length < 2) return false;
		var first = text.charAt(0);
		return (first == '"' || first == "'") && text.charAt(text.length - 1) == first;
	}

	/**
		True when [text] is a plain scalar Unity would write for a number.

		Accepts `0`, `-0`, `1.5`, `-0.02`, `.5`, `1e-05`, `1E+10`, and rejects
		anything with a unit suffix so `10f` stays a string.
	**/
	public static function isNumber(text:String):Bool
	{
		if (text.length == 0) return false;
		var i = 0;
		var n = text.length;
		var c = text.charCodeAt(i);
		if (c == "-".code || c == "+".code)
		{
			i++;
			if (i >= n) return false;
		}
		var digits = 0;
		while (i < n && isDigit(text.charCodeAt(i)))
		{
			i++;
			digits++;
		}
		if (i < n && text.charCodeAt(i) == ".".code)
		{
			i++;
			while (i < n && isDigit(text.charCodeAt(i)))
			{
				i++;
				digits++;
			}
		}
		if (digits == 0) return false;
		if (i < n)
		{
			var e = text.charCodeAt(i);
			if (e != "e".code && e != "E".code) return false;
			i++;
			if (i < n)
			{
				var s = text.charCodeAt(i);
				if (s == "-".code || s == "+".code)
				{
					i++;
				}
			}
			var expDigits = 0;
			while (i < n && isDigit(text.charCodeAt(i)))
			{
				i++;
				expDigits++;
			}
			if (expDigits == 0) return false;
		}
		return i == n;
	}

	inline static function isDigit(code:Int):Bool
	{
		return code >= "0".code && code <= "9".code;
	}

	/** True when [text] looks like a decimal integer, no exponent, no dot. **/
	public static function isInteger(text:String):Bool
	{
		if (text.length == 0) return false;
		var i = text.charCodeAt(0) == "-".code || text.charCodeAt(0) == "+".code ? 1 : 0;
		if (i >= text.length) return false;
		while (i < text.length)
		{
			if (!isDigit(text.charCodeAt(i))) return false;
			i++;
		}
		return true;
	}

	/**
		Parsed 32 bit int, or `null`.

		Range is checked here rather than left to [Std.parseInt], because that
		function is target dependent: on the Neko and eval targets it wraps a value
		outside the 32 bit range, while on others it returns `null`. A caller
		reading a Unity field expects `null` for a value that does not fit, so the
		comparison is done on the digits before parsing.
	**/
	public static function tryInt(text:String):Null<Int>
	{
		var negative = text.length > 0 && text.charCodeAt(0) == "-".code;
		var unsigned = negative ? text.substr(1) : text;
		if (!isInteger(unsigned)) return null;
		var limit = negative ? "2147483648" : "2147483647";
		var trimmed = trimLeadingZeroes(unsigned);
		if (trimmed.length > limit.length) return null;
		if (trimmed.length == limit.length && trimmed > limit) return null;
		return negative ? -Std.parseInt(unsigned) : Std.parseInt(unsigned);
	}

	/** [text] without its leading zeros, or `"0"` when it is all zeros. **/
	static function trimLeadingZeroes(text:String):String
	{
		var index = 0;
		while (index < text.length - 1 && text.charCodeAt(index) == "0".code)
		{
			index++;
		}
		return text.substr(index);
	}

	/**
		Parsed 64 bit int, or `null`.

		Unity file ids and instance ids are 64 bit signed values that can exceed
		`2^53`, so they are parsed here and never through a `Float`. Input that
		overflows a signed 64 bit value returns `null` rather than throwing, which
		keeps a corrupt file readable up to the point of the bad field.
	**/
	public static function tryInt64(text:String):Null<Int64>
	{
		if (!isInteger(text)) return null;
		return int64Of(text);
	}

	/** Number of digits in [text], ignoring a sign. **/
	static function digitsOf(text:String):Int
	{
		var count = 0;
		var i = 0;
		if (text.length > 0 && (text.charCodeAt(0) == "-".code || text.charCodeAt(0) == "+".code)) i = 1;
		while (i < text.length)
		{
			count++;
			i++;
		}
		return count;
	}


	static function int64Of(text:String):Null<Int64>
	{
		try
		{
			return Int64.parseString(text);
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	/** Parsed float, or `null` when [text] is not a plain number. **/
	public static function tryFloat(text:String):Null<Float>
	{
		if (!isNumber(text)) return null;
		var v = Std.parseFloat(text);
		return Math.isNaN(v) ? null : v;
	}

	/** True when [text] is `null` in any of its YAML 1.1 spellings. **/
	public static function isNullText(text:String):Bool
	{
		return text == "" || text == "~" || text == "null" || text == "Null" || text == "NULL";
	}

	/**
		Plain Haxe value for an unquoted scalar: `null`, [Bool], [Int], [Float] or
		the original [String].
	**/
	public static function toHaxe(text:String):Dynamic
	{
		if (isNullText(text)) return null;
		var b = tryBool(text);
		if (b != null) return b;
		if (isInteger(text)) return tryInt64(text);
		var f = tryFloat(text);
		if (f != null) return f;
		return text;
	}

	/**
		Wraps a plain Haxe value into a scalar node.

		Handles `null`, [String], [Bool], [Int] and [Float]. A 64 bit id must be
		passed as text (or through [hxunity.unity.FileId.toStr]) rather than as a
		[haxe.Int64], because an abstract has no runtime type to dispatch on and a
		`Float` cannot hold every Unity file id exactly.
	**/
	public static function node(value:Dynamic):YamlNode
	{
		if (value == null) return new YamlScalar("", Plain);
		if (Std.isOfType(value, String)) return ofString(cast value);
		if (Std.isOfType(value, Bool)) return new YamlScalar((cast value : Bool) ? "1" : "0", Plain);
		if (Std.isOfType(value, Int)) return new YamlScalar(Std.string(cast(value, Int)), Plain);
		if (Std.isOfType(value, Float))
		{
			var f:Float = cast value;
			if (Math.isNaN(f)) return new YamlScalar(".nan", Plain);
			if (f == Math.POSITIVE_INFINITY) return new YamlScalar(".inf", Plain);
			if (f == Math.NEGATIVE_INFINITY) return new YamlScalar("-.inf", Plain);
			return new YamlScalar(Std.string(f), Plain);
		}
		throw new YamlError("cannot convert " + Std.string(value) + " to a YAML scalar");
	}

	/**
		Scalar node for a string, quoted when the text would not survive a plain
		round trip (leading/trailing space, `: `, `#`, flow indicators, or a
		keyword such as `yes`).
	**/
	public static function ofString(text:String):YamlScalar
	{
		return new YamlScalar(text, needsQuoting(text) ? SingleQuoted : Plain);
	}

	/** True when [text] must be quoted to read back as the same string. **/
	public static function needsQuoting(text:String):Bool
	{
		if (text.length == 0) return false;
		var first = text.charAt(0);
		if (first == " " || first == "\t" || text.charAt(text.length - 1) == " ")
		{
			return true;
		}
		if ("-?:,[]{}#&*!|>'\"%@`".indexOf(first) >= 0)
		{
			// `-0.02` and `-1` are valid plain values, `- ` is not.
			if (first != "-" || !isNumber(text)) return true;
		}
		if (text.indexOf(": ") >= 0) return true;
		if (text.indexOf(" #") >= 0) return true;
		if (text.indexOf("\t") >= 0) return true;
		if (text.indexOf("\n") >= 0) return true;
		if (isTrue(text) || isFalse(text) || isNullText(text)) return true;
		if (first == "{" || first == "[" || first == "}" || first == "]") return true;
		return false;
	}
}
