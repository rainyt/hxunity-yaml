package hxunity.unity;

import haxe.Int64;

/**
	What a serialised reference turned out to point at.

	This exists because "resolution failed" is not one state but several, and they
	need different answers from the caller:

	* a **local** reference (`{fileID: 123}`) is already inside the file being read,
	* a **built-in** reference names engine content that has no file to open,
	* a **missing** reference names a GUID that is not in the project, which usually
	  means the asset was deleted or the project is incomplete.

	Collapsing those into `null` loses exactly the information needed to explain
	what happened to a reference.
**/
class ResolvedReference
{
	/** The reference that was resolved. **/
	public var reference(default, null):UnityReference;

	/**
		The asset the GUID names, or `null`.

		`null` for a local reference (no GUID was involved) and for a missing one.
		Built-in references get a synthetic entry with no [AssetEntry.path], so that
		the object id is still available.
	**/
	public var entry(default, null):AssetEntry;

	/** Where the target lives. **/
	public var origin(default, null):Origin;

	/** The `fileID` from the reference. **/
	public var fileId(default, null):Int64;

	/**
		True when [fileId] is the target asset's main object.

		For a built-in resource this is always true, because the id *is* the object.
		A prefab has no main object, so it is always false there.
	**/
	public var isMainObject(default, null):Bool;

	public function new(reference:UnityReference, entry:AssetEntry, origin:Origin, fileId:Int64, isMainObject:Bool)
	{
		this.reference = reference;
		this.entry = entry;
		this.origin = origin;
		this.fileId = fileId;
		this.isMainObject = isMainObject;
	}

	/** True when the target is a file on disk that can be read. **/
	public function hasFile():Bool
	{
		return entry != null && entry.path != null;
	}

	/** True when the target is content built into Unity. **/
	public function isBuiltin():Bool
	{
		return origin == Origin.Builtin;
	}

	/** True when the reference stays inside the file it was written in. **/
	public function isLocal():Bool
	{
		return origin == Origin.Local;
	}

	/** True when no asset is known under the reference's GUID. **/
	public function isMissing():Bool
	{
		return origin == Origin.Missing;
	}

	/** Kind of the target asset, or [AssetKind.Unknown] when there is none. **/
	public function kind():AssetKind
	{
		return entry == null ? AssetKind.Unknown : entry.kind;
	}

	/** Path of the target relative to the project root, or `null`. **/
	public function path():String
	{
		return entry == null ? null : entry.path;
	}

	public function toString():String
	{
		if (isLocal()) return 'ResolvedReference(local fileID=${Int64.toStr(fileId)})';
		if (isBuiltin()) return 'ResolvedReference(builtin fileID=${Int64.toStr(fileId)})';
		if (isMissing()) return 'ResolvedReference(missing guid=${reference == null ? "?" : reference.guid})';
		return 'ResolvedReference(${entry.path} ${entry.kind}${isMainObject ? " main" : ""})';
	}
}
