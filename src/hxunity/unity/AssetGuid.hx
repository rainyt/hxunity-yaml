package hxunity.unity;

import hxunity.yaml.Xorshift;

/**
	Unity asset GUIDs: the 32 hex digit identifier every `.meta` file carries.

	A GUID is what makes a reference survive a file being renamed or moved, so
	the format is not negotiable:

	```yaml
	guid: 9e613c018e232044db897e24a5e4fd3f
	```

	thirty two lowercase hexadecimal digits, no dashes, no braces, no `0x`.

	## Generating one

	[generate] draws from the shared [Xorshift] source rather than `Std.random`,
	for the reason recorded there: the standard generator is not seeded on every
	target, and an unseeded `Std.random` throws on Neko.

	Two values are never handed out:

	* the **all zero** GUID, which is not an asset: Unity writes it as the "no
	  reference" case next to `fileID: 0`;
	* the **built-in** GUIDs of [BuiltinResources], which name engine resources
	  that exist in every project. A generated `.meta` carrying one of those
	  would be a file no reference could ever reach.

	The randomness is generated, not derived from the path, so exporting the same
	PSD twice produces different GUIDs — which is correct: the first export's
	GUIDs are already referenced by files on disk, and reusing them for different
	content is what makes an asset silently change meaning.
**/
class AssetGuid
{
	/** Digits in a GUID, the length Unity writes. **/
	public static inline var LENGTH = 32;

	/** The all zero GUID, Unity's "no asset". **/
	public static inline var NONE = "00000000000000000000000000000000";

	/** How many draws [generate] takes before giving up on avoiding the reserved values. **/
	static inline var ATTEMPTS = 64;

	/**
		A fresh GUID: 32 lowercase hex digits, never all zero and never built-in.

		The reserved values are astronomically unlikely to be drawn — the
		built-in GUIDs alone need a word above `0x7FFFFFFF`, which this generator
		cannot produce — but the check is kept because a wrong GUID fails
		silently, months later, as a missing texture.
	**/
	public static function generate():String
	{
		var candidate = randomText();
		var attempts = 0;
		while (!isUsable(candidate) && attempts < ATTEMPTS)
		{
			candidate = randomText();
			attempts++;
		}
		return candidate;
	}

	/**
		A fresh GUID that [taken] does not already report.

		The predicate form is what a caller with an index in hand wants;
		[AssetGuidIndex.newGuid] is the same thing without the closure.
	**/
	public static function generateUnique(taken:String->Bool):String
	{
		if (taken == null) return generate();
		var candidate = generate();
		var attempts = 0;
		while (taken(candidate) && attempts < ATTEMPTS)
		{
			candidate = generate();
			attempts++;
		}
		return candidate;
	}

	/** 128 bits of randomness as 32 lowercase hex digits. **/
	static function randomText():String
	{
		var bytes = Xorshift.bytes(16);
		var sb = new StringBuf();
		for (i in 0...16)
		{
			sb.add(StringTools.hex(bytes.get(i), 2));
		}
		return sb.toString().toLowerCase();
	}

	/**
		True when [text] is exactly 32 hexadecimal digits.

		Case is not checked here: Unity writes lowercase, but an upper case GUID
		read from a hand edited file still names a real asset, so
		[normalise] lowercases instead of rejecting it.
	**/
	public static function isValid(text:String):Bool
	{
		if (text == null || text.length != LENGTH) return false;
		for (i in 0...text.length)
		{
			var code = text.charCodeAt(i);
			var digit = code >= "0".code && code <= "9".code;
			var lower = code >= "a".code && code <= "f".code;
			var upper = code >= "A".code && code <= "F".code;
			if (!digit && !lower && !upper) return false;
		}
		return true;
	}

	/**
		The canonical spelling of [text]: trimmed and lowercased.

		Returns `null` for `null`, so it can be applied to a value that may be
		absent without a caller side check. Text that is not a GUID is still
		lowercased rather than rejected — the index compares GUIDs as text, and a
		lookup for something malformed should simply miss.
	**/
	public static function normalise(text:String):String
	{
		return text == null ? null : StringTools.trim(text).toLowerCase();
	}

	/** True when [text] is the all zero GUID, i.e. "no asset". **/
	public static function isNone(text:String):Bool
	{
		if (text == null) return false;
		var key = normalise(text);
		if (key.length == 0) return false;
		// Unity writes the zero GUID with any number of leading digits in older
		// files, so the test is "every digit is a zero" rather than an exact match.
		for (i in 0...key.length)
		{
			if (key.charCodeAt(i) != "0".code) return false;
		}
		return true;
	}

	/** True when [text] is one of the built-in GUIDs of [BuiltinResources]. **/
	public static function isBuiltin(text:String):Bool
	{
		return text != null && BuiltinResources.isBuiltinGuid(normalise(text));
	}

	/** True when [text] is a well formed GUID that names a project asset. **/
	public static function isUsable(text:String):Bool
	{
		return isValid(text) && !isNone(text) && !isBuiltin(text);
	}
}
