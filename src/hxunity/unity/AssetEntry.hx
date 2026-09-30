package hxunity.unity;

import haxe.Int64;

/**
	One asset in the GUID index.

	This is the record the cache stores and the type every lookup returns. Fields
	are plain rather than `(default, null)` because the index builds entries while
	parsing a `.meta` file, and a class rather than an anonymous structure so a
	caller can pass one around without the compiler losing the type.
**/
class AssetEntry
{
	/** Lowercase 32 digit asset GUID, as written in the `.meta` file. **/
	public var guid:String;

	/**
		Path relative to the project root, with forward slashes.

		`null` for a built-in resource, which has no file.
	**/
	public var path:String;

	/** Kind derived from the importer section and the extension. **/
	public var kind:AssetKind;

	/**
		File id of the asset's main object, or `null` when there is none.

		Taken from `mainObjectFileID` when the importer writes it, otherwise from
		[BuiltinResources.mainObjectFileId]. A prefab has no main object, because it
		is a tree of GameObjects, so this stays `null` there.
	**/
	public var mainId:Int64;

	/** Where the asset lives. **/
	public var origin:Origin;

	/** Importer section name read from the `.meta` file, e.g. `TextureImporter`. **/
	public var importer:String;

	public function new(guid:String, path:String, kind:AssetKind, origin:Origin, mainId:Int64 = null, importer:String = null)
	{
		this.guid = guid;
		this.path = path;
		this.kind = kind;
		this.origin = origin;
		this.mainId = mainId;
		this.importer = importer;
	}

	/** File name without the directory, or `null` for a built-in. **/
	public function fileName():String
	{
		if (path == null) return null;
		var slash = path.lastIndexOf("/");
		return slash < 0 ? path : path.substr(slash + 1);
	}

	/** Extension without the dot, lowercased, or `null` when there is none. **/
	public function extension():String
	{
		var name = fileName();
		if (name == null) return null;
		var dot = name.lastIndexOf(".");
		return dot < 0 ? null : name.substr(dot + 1).toLowerCase();
	}

	public function toString():String
	{
		var id = mainId == null ? "-" : Int64.toStr(mainId);
		return 'AssetEntry($guid $kind $origin ${path == null ? "<builtin>" : path} main=$id)';
	}
}
