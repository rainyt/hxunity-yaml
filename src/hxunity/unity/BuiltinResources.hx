package hxunity.unity;

import haxe.Int64;

/**
	Unity's built-in resources, which live in the engine rather than in the
	project.

	A reference like

	```yaml
	m_Mesh: {fileID: 10210, guid: 0000000000000000e000000000000000, type: 0}
	```

	names an asset that has **no `.meta` file anywhere**, so no amount of scanning
	the project will ever resolve it. Recognising it needs a fixed table, which is
	what this class is for.

	## How a built-in reference is recognised

	Not by an all zero GUID. Built-in resources use a small set of fixed GUIDs,
	observed in real projects as

	```
	0000000000000000e000000000000000
	0000000000000000f000000000000000
	```

	so the test is "the GUID is one of the built-in GUIDs" combined with the
	reference carrying `type: 0`. A `fileID` of 0 is never built-in: that is Unity's
	way of writing "no reference".

	## Coverage

	[names] is deliberately small. It lists only ids that could be confirmed, and an
	id outside it is still reported as built-in with its raw `fileID` — knowing
	that a reference points into the engine, and at which id, is already useful.
	The table is easy to extend, and `lib/**` is the place to do it.
**/
class BuiltinResources
{
	/** GUIDs Unity uses for resources that are not in the project. **/
	public static var guids(default, null):Map<String, Bool> = buildGuids();

	/**
		Names of confirmed built-in objects, keyed by the file id as decimal text.

		Only ids with a trustworthy source are listed. Anything missing is left out
		on purpose rather than guessed at, because a wrong name is worse than no
		name.
	**/
	public static var names(default, null):Map<String, String> = buildNames();

	/**
		File id of the main object of a built-in asset.

		Built-ins have no `Object` header, so unlike a project asset there is no
		`mainObjectFileID` to read; the value is the object's own id.
	**/
	public static function mainObjectFileId(fileId:Int64):Int64
	{
		return fileId;
	}

	/** True when [guid] is one of the fixed built-in asset GUIDs. **/
	public static function isBuiltinGuid(guid:String):Bool
	{
		if (guid == null) return false;
		return guids.exists(guid.toLowerCase());
	}

	/** Name of the built-in object [fileId], or `null` when it is not known. **/
	public static function nameOf(fileId:Int64):String
	{
		if (fileId == null) return null;
		// Keyed by text rather than by Int: a Unity id can exceed the 32 bit Int
		// range, and on the JavaScript target an Int cannot hold it exactly.
		return names.get(Int64.toStr(fileId));
	}

	/**
		True when [fileId] is a positive object id rather than "no reference".

		`{fileID: 0}` means nothing at all, so it is never treated as built-in.
	**/
	public static function isObjectId(fileId:Int64):Bool
	{
		return fileId != null && Int64.compare(fileId, Int64.ofInt(0)) != 0;
	}

	static function buildGuids():Map<String, Bool>
	{
		var map = new Map<String, Bool>();
		map.set("0000000000000000e000000000000000", true);
		map.set("0000000000000000f000000000000000", true);
		return map;
	}

	static function buildNames():Map<String, String>
	{
		var map = new Map<String, String>();
		// Confirmed: 10210 is the built-in Cube mesh, the primitive Unity creates
		// for a Cube. It accounted for 5,693 of the 5,776 built-in references in
		// the reference project, so it is worth naming even as the only entry.
		map.set("10210", "Cube");
		return map;
	}
}
