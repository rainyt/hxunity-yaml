package hxunity.yaml;

import haxe.Int64;

/** Small string helpers shared by the YAML layer. **/
class Strings
{
	/** A string of [count] spaces, or `""` when [count] is not positive. **/
	public static function spaces(count:Int):String
	{
		if (count <= 0) return "";
		var sb = new StringBuf();
		var i = 0;
		while (i < count)
		{
			sb.add(" ");
			i++;
		}
		return sb.toString();
	}

	/**
		Indents every line of [text] by [indent] spaces.

		Only lines after the first are touched, because the first line of a
		scalar is written by the caller right after `key: `. Multi line values
		such as `_serializedGraph` therefore line up the way Unity writes them.
	**/
	public static function indentRest(text:String, indent:Int):String
	{
		if (indent <= 0 || text.indexOf("\n") < 0) return text;
		var pad = spaces(indent);
		return text.split("\n").join("\n" + pad);
	}

	/**
		Splits [text] into lines, keeping empty trailing lines out.

		Handles `\n`, `\r\n` and lone `\r`, because a prefab may be checked out
		with any of them.
	**/
	public static function splitLines(text:String):Array<String>
	{
		var out = [];
		var start = 0;
		var i = 0;
		var n = text.length;
		while (i < n)
		{
			var c = text.charCodeAt(i);
			if (c == "\n".code)
			{
				out.push(text.substring(start, i));
				i++;
				start = i;
			}
			else if (c == "\r".code)
			{
				out.push(text.substring(start, i));
				i++;
				if (i < n && text.charCodeAt(i) == "\n".code) i++;
				start = i;
			}
			else
			{
				i++;
			}
		}
		out.push(text.substring(start, n));
		return out;
	}

	/**
		Detects the dominant line ending of [text].

		Unity writes `\r\n` on Windows and `\n` elsewhere, and a document that is
		rewritten must keep the original choice so version control does not show
		a whole file change.
	**/
	public static function detectLineEnding(text:String):String
	{
		var crlf = 0;
		var lf = 0;
		var i = 0;
		while (i < text.length)
		{
			var c = text.charCodeAt(i);
			if (c == "\n".code)
			{
				if (i > 0 && text.charCodeAt(i - 1) == "\r".code) crlf++ else lf++;
				i++;
			}
			else
			{
				i++;
			}
		}
		if (crlf == 0 && lf == 0) return "\n";
		return crlf >= lf ? "\r\n" : "\n";
	}

	/** `haxe.Int64` as a decimal string. **/
	public static inline function int64(value:Int64):String
	{
		return Int64.toStr(value);
	}
}
